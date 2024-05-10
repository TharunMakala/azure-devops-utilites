package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/azure-devops-utils/pipeline-monitor/internal/client"
	"github.com/azure-devops-utils/pipeline-monitor/internal/monitor"
	"github.com/spf13/cobra"
)

var (
	daysBack   int
	outputJSON bool
)

var metricsCmd = &cobra.Command{
	Use:   "metrics",
	Short: "Show pipeline performance metrics",
	RunE: func(cmd *cobra.Command, args []string) error {
		if orgURL == "" || pat == "" || project == "" {
			return fmt.Errorf("org, pat, and project are required")
		}

		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		azClient, err := client.New(orgURL, pat)
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		return monitor.PrintMetrics(ctx, azClient, project, daysBack, outputJSON)
	},
}

func init() {
	metricsCmd.Flags().IntVar(&daysBack, "days", 7, "Number of days to analyze")
	metricsCmd.Flags().BoolVar(&outputJSON, "json", false, "Output as JSON")
	rootCmd.AddCommand(metricsCmd)
}
