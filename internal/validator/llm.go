package validator

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/das/faa-knowledge/internal/llm"
)

// LLMClient talks to a llama.cpp OpenAI-compatible API.
type LLMClient struct {
	Client *llm.Client
}

// NewLLMClient creates a client pointed at the given llama.cpp base URL.
func NewLLMClient(baseURL string) *LLMClient {
	return &LLMClient{Client: llm.NewClient(baseURL)}
}

// NewLLMClientWith creates a client with an explicit model name and optional
// reasoning mode (GLM). When think is set it enables thinking, raises the
// timeout and max_tokens to leave room for the chain-of-thought plus JSON.
func NewLLMClientWith(baseURL, model string, think bool) *LLMClient {
	c := llm.NewClient(baseURL).WithModel(model)
	if think {
		c = c.WithThinking(true).WithMaxTokens(16000).WithTimeout(600 * time.Second)
	}
	return &LLMClient{Client: c}
}

const systemPrompt = `You are an FAA Designated Pilot Examiner and aviation knowledge expert.
You are reviewing multiple-choice questions for a Private Pilot License study tool.

For each question, evaluate:
1. Is the question clearly worded and unambiguous?
2. Is the correct_answer actually correct per FAA publications (PHAK, AFH)?
3. Are the distractors (wrong answers) plausible but clearly incorrect?
4. Is the explanation accurate?

When reference text from the FAA handbook is provided, use it as the authoritative source for evaluating correctness. The reference text is copied directly from the official FAA publication and should be treated as ground truth.

Respond with JSON only.`

const userPromptTemplate = `Review this aviation knowledge question:

%s

Respond with this exact JSON structure:
{
  "verdict": "pass" or "fail",
  "issues": [],
  "suggested_question": "..." or null,
  "suggested_correct_answer": "..." or null,
  "suggested_distractors": [...] or null,
  "suggested_explanation": "..." or null,
  "reasoning": "Brief explanation of your assessment"
}

Set verdict to "pass" if everything is correct. Set to "fail" if anything is wrong.
Only populate suggested_* fields if you have a concrete improvement. Leave as null if the original is fine.`

// questionPayload is the subset of fields we send to the LLM for review.
type questionPayload struct {
	Question      string   `json:"question"`
	CorrectAnswer string   `json:"correct_answer"`
	Distractors   []string `json:"distractors"`
	Explanation   string   `json:"explanation"`
	ReferenceText string   `json:"reference_text,omitempty"`
}

// Review sends a single question to the LLM and returns its assessment.
func (c *LLMClient) Review(ctx context.Context, q questionPayload) (ReviewResult, error) {
	qJSON, err := json.MarshalIndent(q, "", "  ")
	if err != nil {
		return ReviewResult{}, fmt.Errorf("marshal question: %w", err)
	}

	userPrompt := fmt.Sprintf(userPromptTemplate, string(qJSON))

	if q.ReferenceText != "" {
		userPrompt += fmt.Sprintf("\n\nSource text from FAA handbook:\n\"%s\"", q.ReferenceText)
	}

	var result ReviewResult
	if err := c.Client.CompleteJSON(ctx, systemPrompt, userPrompt, &result); err != nil {
		return ReviewResult{}, err
	}

	return result, nil
}
