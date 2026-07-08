package llm

import "testing"

func TestExtractJSON(t *testing.T) {
	cases := []struct{ in, want string }{
		{`{"a":1}`, `{"a":1}`},
		{"```json\n{\"a\":1}\n```", `{"a":1}`},
		{"```\n{\"a\":1}\n```", `{"a":1}`},
		{"<think>reasoning</think>{\"a\":1}", `{"a":1}`},
		{"prefix {\"a\":1} suffix", `{"a":1}`},
		{"[1,2,3]", `[1,2,3]`},
		// reasoning model reconsiders: keep the LAST complete object
		{`{"v":"pass"} Wait, on reflection {"v":"fail"}`, `{"v":"fail"}`},
		// braces inside strings must not confuse the scanner
		{`{"note":"has } and { inside"}`, `{"note":"has } and { inside"}`},
		{"Let me evaluate.\n1. good\nFinal: {\"verdict\":\"pass\",\"issues\":[]}", `{"verdict":"pass","issues":[]}`},
	}
	for _, c := range cases {
		if got := extractJSON(c.in); got != c.want {
			t.Errorf("extractJSON(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
