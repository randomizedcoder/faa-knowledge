package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	BaseURL     string
	Model       string
	Temperature float64
	Timeout     time.Duration
	// Thinking controls the reasoning mode of hybrid models (e.g. GLM) via
	// chat_template_kwargs.enable_thinking. nil means "don't send the field"
	// so llama.cpp servers that don't understand it (the l2 pipeline) behave
	// exactly as before. When true, response_format:json_object is dropped
	// because a JSON grammar constraint conflicts with visible chain-of-thought.
	Thinking   *bool
	MaxTokens  int
	httpClient http.Client
}

func NewClient(baseURL string) *Client {
	c := &Client{
		BaseURL:     baseURL,
		Model:       "local",
		Temperature: 0.1,
		Timeout:     120 * time.Second,
	}
	c.httpClient = http.Client{Timeout: c.Timeout}
	return c
}

func (c *Client) WithTemperature(t float64) *Client {
	cp := *c
	cp.Temperature = t
	return &cp
}

func (c *Client) WithTimeout(d time.Duration) *Client {
	cp := *c
	cp.Timeout = d
	cp.httpClient = http.Client{Timeout: d}
	return &cp
}

// WithModel sets the model name sent to the server (e.g. "/model" for GLM).
func (c *Client) WithModel(m string) *Client {
	cp := *c
	if m != "" {
		cp.Model = m
	}
	return &cp
}

// WithThinking enables/disables the model's reasoning mode via
// chat_template_kwargs.enable_thinking.
func (c *Client) WithThinking(enabled bool) *Client {
	cp := *c
	cp.Thinking = &enabled
	return &cp
}

// WithMaxTokens caps the completion length (0 = server default).
func (c *Client) WithMaxTokens(n int) *Client {
	cp := *c
	cp.MaxTokens = n
	return &cp
}

type chatRequest struct {
	Model              string          `json:"model"`
	Messages           []chatMessage   `json:"messages"`
	Temperature        float64         `json:"temperature"`
	ResponseFormat     *responseFormat `json:"response_format,omitempty"`
	ChatTemplateKwargs map[string]any  `json:"chat_template_kwargs,omitempty"`
	MaxTokens          int             `json:"max_tokens,omitempty"`
	Stream             bool            `json:"stream"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type responseFormat struct {
	Type string `json:"type"`
}

type chatResponse struct {
	Choices []chatChoice `json:"choices"`
}

type chatChoice struct {
	Message chatMessageResponse `json:"message"`
}

type chatMessageResponse struct {
	Role             string `json:"role"`
	Content          string `json:"content"`
	ReasoningContent string `json:"reasoning_content"`
}

// Complete sends system+user messages and returns the raw content string.
// Always uses response_format: json_object.
func (c *Client) Complete(ctx context.Context, system, user string) (string, error) {
	reqBody := chatRequest{
		Model: c.Model,
		Messages: []chatMessage{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
		Temperature:    c.Temperature,
		ResponseFormat: &responseFormat{Type: "json_object"},
		MaxTokens:      c.MaxTokens,
		Stream:         false,
	}

	// Hybrid reasoning models (GLM): forward enable_thinking. When thinking is
	// on, drop the json_object grammar — it can't coexist with visible
	// chain-of-thought; CompleteJSON extracts the JSON from the output instead.
	if c.Thinking != nil {
		reqBody.ChatTemplateKwargs = map[string]any{"enable_thinking": *c.Thinking}
		if *c.Thinking {
			reqBody.ResponseFormat = nil
		}
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.BaseURL+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("llm request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("llm returned %d: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return "", fmt.Errorf("parse chat response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("llm returned no choices")
	}

	msg := chatResp.Choices[0].Message
	content := msg.Content
	if content == "" {
		content = msg.ReasoningContent
	}
	return content, nil
}

// CompleteJSON calls Complete then unmarshals the result into dest.
func (c *Client) CompleteJSON(ctx context.Context, system, user string, dest interface{}) error {
	content, err := c.Complete(ctx, system, user)
	if err != nil {
		return err
	}

	clean := extractJSON(content)
	if err := json.Unmarshal([]byte(clean), dest); err != nil {
		return fmt.Errorf("parse json response: %w\nraw: %s", err, content)
	}

	return nil
}

// extractJSON pulls a JSON value out of an LLM response that may wrap it in
// markdown fences or surround it with reasoning text (e.g. GLM thinking output).
// It strips ```json fences, then scans for balanced, string-aware top-level
// {...}/[...] groups and returns the LAST complete one — reasoning models often
// emit a first answer, reconsider ("Wait, ..."), then emit a corrected final
// JSON, so the last balanced value is the one to trust. Returns the input
// unchanged if no complete JSON value is found.
func extractJSON(s string) string {
	s = strings.TrimSpace(s)

	// Strip a fenced code block if present: ```json ... ``` or ``` ... ```
	if strings.HasPrefix(s, "```") {
		if i := strings.IndexByte(s, '\n'); i != -1 {
			s = s[i+1:]
		}
		if i := strings.LastIndex(s, "```"); i != -1 {
			s = s[:i]
		}
		s = strings.TrimSpace(s)
	}

	best := ""
	inStr := false
	esc := false
	depth := 0
	start := -1
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if inStr {
			switch {
			case esc:
				esc = false
			case ch == '\\':
				esc = true
			case ch == '"':
				inStr = false
			}
			continue
		}
		switch ch {
		case '"':
			inStr = true
		case '{', '[':
			if depth == 0 {
				start = i
			}
			depth++
		case '}', ']':
			if depth > 0 {
				depth--
				if depth == 0 && start >= 0 {
					best = s[start : i+1] // keep the last complete top-level value
				}
			}
		}
	}
	if best != "" {
		return best
	}
	return s
}
