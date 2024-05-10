package monitor

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/azure-devops-utils/pipeline-monitor/internal/client"
	"github.com/fatih/color"
	"github.com/rodaine/table"
)

type Options struct {
	Interval    time.Duration
	PipelineIDs []int
	AlertOnFail bool
}

type Monitor struct {
	client  *client.Client
	project string
	opts    Options
	seen    map[int]string
}

func New(c *client.Client, project string, opts Options) *Monitor {
	return &Monitor{
		client:  c,
		project: project,
		opts:    opts,
		seen:    make(map[int]string),
	}
}

func (m *Monitor) Start(ctx context.Context) error {
	color.Cyan("Monitoring pipelines in %s (interval: %s)\n", m.project, m.opts.Interval)
	color.Cyan("Press Ctrl+C to stop\n\n")

	ticker := time.NewTicker(m.opts.Interval)
	defer ticker.Stop()

	// Initial check
	if err := m.check(ctx); err != nil {
		color.Red("Error: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := m.check(ctx); err != nil {
				color.Red("Error: %v", err)
			}
		}
	}
}

func (m *Monitor) check(ctx context.Context) error {
	runs, err := m.client.GetRuns(m.project, 25)
	if err != nil {
		return err
	}

	for _, run := range runs {
		prevState, exists := m.seen[run.ID]
		currentState := run.State + ":" + run.Result

		if !exists || prevState != currentState {
			m.seen[run.ID] = currentState
			m.printRunUpdate(run, !exists)
		}
	}

	return nil
}

func (m *Monitor) printRunUpdate(run client.PipelineRun, isNew bool) {
	status := formatStatus(run.State, run.Result)
	prefix := "UPDATE"
	if isNew {
		prefix = "NEW"
	}

	fmt.Printf("[%s] %s %-6s | %-30s | #%-6d | %s\n",
		time.Now().Format("15:04:05"),
		prefix,
		status,
		truncate(run.Pipeline.Name, 30),
		run.ID,
		run.CreatedDate.Local().Format("Jan 02 15:04"),
	)

	if m.opts.AlertOnFail && run.Result == "failed" {
		color.Red("  ⚠ FAILURE: %s (Run #%d)", run.Pipeline.Name, run.ID)
	}
}

func formatStatus(state, result string) string {
	switch {
	case state == "inProgress":
		return color.YellowString("⟳ RUN")
	case result == "succeeded":
		return color.GreenString("✓ OK")
	case result == "failed":
		return color.RedString("✗ FAIL")
	case result == "canceled":
		return color.HiBlackString("⊘ SKIP")
	default:
		return color.WhiteString("? " + state)
	}
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s + strings.Repeat(" ", max-len(s))
	}
	return s[:max-3] + "..."
}

func PrintStatus(ctx context.Context, c *client.Client, project string, top int, showAll bool) error {
	runs, err := c.GetRuns(project, top)
	if err != nil {
		return err
	}

	headerFmt := color.New(color.FgCyan, color.Underline).SprintfFunc()
	tbl := table.New("ID", "Pipeline", "Status", "Result", "Started", "Duration")
	tbl.WithHeaderFormatter(headerFmt)

	for _, run := range runs {
		if !showAll && run.Result == "succeeded" {
			continue
		}
		duration := "running"
		if run.FinishedDate != nil {
			duration = run.FinishedDate.Sub(run.CreatedDate).Round(time.Second).String()
		}
		tbl.AddRow(run.ID, run.Pipeline.Name, run.State, run.Result,
			run.CreatedDate.Local().Format("Jan 02 15:04"), duration)
	}

	tbl.Print()
	return nil
}

func PrintMetrics(ctx context.Context, c *client.Client, project string, days int, jsonOut bool) error {
	since := time.Now().AddDate(0, 0, -days)
	runs, err := c.GetRunsSince(project, since)
	if err != nil {
		return err
	}

	stats := make(map[string]*pipelineStats)
	for _, run := range runs {
		name := run.Pipeline.Name
		if _, ok := stats[name]; !ok {
			stats[name] = &pipelineStats{Name: name}
		}
		s := stats[name]
		s.Total++
		switch run.Result {
		case "succeeded":
			s.Succeeded++
		case "failed":
			s.Failed++
		}
		if run.FinishedDate != nil {
			dur := run.FinishedDate.Sub(run.CreatedDate)
			s.TotalDuration += dur
			if dur > s.MaxDuration {
				s.MaxDuration = dur
			}
		}
	}

	headerFmt := color.New(color.FgCyan, color.Underline).SprintfFunc()
	tbl := table.New("Pipeline", "Runs", "Pass", "Fail", "Rate", "Avg Duration", "Max Duration")
	tbl.WithHeaderFormatter(headerFmt)

	for _, s := range stats {
		rate := float64(s.Succeeded) / float64(s.Total) * 100
		avgDur := time.Duration(0)
		if s.Total > 0 {
			avgDur = s.TotalDuration / time.Duration(s.Total)
		}
		tbl.AddRow(s.Name, s.Total, s.Succeeded, s.Failed,
			fmt.Sprintf("%.0f%%", rate),
			avgDur.Round(time.Second),
			s.MaxDuration.Round(time.Second))
	}

	tbl.Print()
	return nil
}

type pipelineStats struct {
	Name          string
	Total         int
	Succeeded     int
	Failed        int
	TotalDuration time.Duration
	MaxDuration   time.Duration
}
