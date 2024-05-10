package client

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
	authHeader string
}

type PipelineRun struct {
	ID         int       `json:"id"`
	Name       string    `json:"name"`
	State      string    `json:"state"`
	Result     string    `json:"result"`
	Pipeline   Pipeline  `json:"pipeline"`
	CreatedDate time.Time `json:"createdDate"`
	FinishedDate *time.Time `json:"finishedDate"`
	URL        string    `json:"url"`
}

type Pipeline struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type RunListResponse struct {
	Count int           `json:"count"`
	Value []PipelineRun `json:"value"`
}

func New(orgURL, pat string) (*Client, error) {
	if orgURL == "" || pat == "" {
		return nil, fmt.Errorf("organization URL and PAT are required")
	}

	auth := base64.StdEncoding.EncodeToString([]byte(":" + pat))

	return &Client{
		baseURL: orgURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		authHeader: "Basic " + auth,
	}, nil
}

func (c *Client) GetRuns(project string, top int) ([]PipelineRun, error) {
	url := fmt.Sprintf("%s/%s/_apis/build/builds?$top=%d&api-version=7.1", c.baseURL, project, top)
	return c.fetchRuns(url)
}

func (c *Client) GetRunsByPipeline(project string, pipelineID, top int) ([]PipelineRun, error) {
	url := fmt.Sprintf("%s/%s/_apis/build/builds?definitions=%d&$top=%d&api-version=7.1",
		c.baseURL, project, pipelineID, top)
	return c.fetchRuns(url)
}

func (c *Client) GetRunsSince(project string, since time.Time) ([]PipelineRun, error) {
	url := fmt.Sprintf("%s/%s/_apis/build/builds?minTime=%s&api-version=7.1",
		c.baseURL, project, since.Format(time.RFC3339))
	return c.fetchRuns(url)
}

func (c *Client) fetchRuns(url string) ([]PipelineRun, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.authHeader)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("API request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API returned %d: %s", resp.StatusCode, string(body))
	}

	var result RunListResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result.Value, nil
}
