package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	orgURL string
	pat    string
	project string
)

var rootCmd = &cobra.Command{
	Use:   "pipeline-monitor",
	Short: "Monitor Azure DevOps pipeline runs in real-time",
	Long: `Pipeline Monitor watches Azure DevOps pipeline runs and provides
real-time status updates, failure alerts, and performance metrics.`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&orgURL, "org", os.Getenv("AZDO_ORG_URL"), "Azure DevOps organization URL")
	rootCmd.PersistentFlags().StringVar(&pat, "pat", os.Getenv("AZDO_PAT"), "Personal access token")
	rootCmd.PersistentFlags().StringVar(&project, "project", os.Getenv("AZDO_PROJECT"), "Project name")
}
