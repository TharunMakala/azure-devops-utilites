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
	topN    int
	showAll bool
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show current pipeline status summary",
	RunE: func(cmd *cobra.Command, args []string) error {
		if orgURL == "" || pat == "" || project == "" {
			return fmt.Errorf("org, pat, and project are required")
		}

		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		azClient, err := client.New(orgURL, pat)
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		return monitor.PrintStatus(ctx, azClient, project, topN, showAll)
	},
}

func init() {
	statusCmd.Flags().IntVar(&topN, "top", 10, "Number of recent runs to show")
	statusCmd.Flags().BoolVar(&showAll, "all", false, "Show all pipelines including successful")
	rootCmd.AddCommand(statusCmd)
}
