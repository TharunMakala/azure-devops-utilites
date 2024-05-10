package cmd

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/azure-devops-utils/pipeline-monitor/internal/client"
	"github.com/azure-devops-utils/pipeline-monitor/internal/monitor"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var (
	interval    int
	pipelineIDs []int
	alertOnFail bool
)

var watchCmd = &cobra.Command{
	Use:   "watch",
	Short: "Watch pipeline runs in real-time",
	RunE: func(cmd *cobra.Command, args []string) error {
		if orgURL == "" || pat == "" || project == "" {
			return fmt.Errorf("org, pat, and project are required (use flags or AZDO_* env vars)")
		}

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			<-sigCh
			color.Yellow("\nShutting down gracefully...")
			cancel()
		}()

		azClient, err := client.New(orgURL, pat)
		if err != nil {
			return fmt.Errorf("failed to create client: %w", err)
		}

		mon := monitor.New(azClient, project, monitor.Options{
			Interval:    time.Duration(interval) * time.Second,
			PipelineIDs: pipelineIDs,
			AlertOnFail: alertOnFail,
		})

		return mon.Start(ctx)
	},
}

func init() {
	watchCmd.Flags().IntVar(&interval, "interval", 30, "Poll interval in seconds")
	watchCmd.Flags().IntSliceVar(&pipelineIDs, "pipelines", nil, "Specific pipeline IDs to watch (default: all)")
	watchCmd.Flags().BoolVar(&alertOnFail, "alert", true, "Alert on pipeline failures")
	rootCmd.AddCommand(watchCmd)
}
