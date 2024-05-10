package notify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type SlackNotifier struct {
	webhookURL string
	client     *http.Client
}

type slackMessage struct {
	Text        string       `json:"text"`
	Attachments []attachment `json:"attachments,omitempty"`
}

type attachment struct {
	Color  string `json:"color"`
	Title  string `json:"title"`
	Text   string `json:"text"`
	Footer string `json:"footer"`
}

func NewSlackNotifier(webhookURL string) *SlackNotifier {
	return &SlackNotifier{
		webhookURL: webhookURL,
		client:     &http.Client{Timeout: 10 * time.Second},
	}
}

func (s *SlackNotifier) SendFailureAlert(pipelineName string, runID int, errorMsg string) error {
	msg := slackMessage{
		Text: fmt.Sprintf("Pipeline failure: %s", pipelineName),
		Attachments: []attachment{
			{
				Color:  "#ff0000",
				Title:  fmt.Sprintf("Run #%d Failed", runID),
				Text:   errorMsg,
				Footer: fmt.Sprintf("Pipeline Monitor | %s", time.Now().Format(time.RFC822)),
			},
		},
	}

	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	resp, err := s.client.Post(s.webhookURL, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("slack notification failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("slack returned status %d", resp.StatusCode)
	}

	return nil
}
