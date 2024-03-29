package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/rancher/octopus/pkg/util/version/verflag"
	"github.com/rancher/octopus/template/adaptor/pkg/template"
)

const (
	name        = "template"
	description = ``
)

func newCommand() *cobra.Command {
	var c = &cobra.Command{
		Use:  name,
		Long: description,
		RunE: func(cmd *cobra.Command, args []string) error {
			verflag.PrintAndExitIfRequested(name)
			return template.Run()
		},
	}

	verflag.AddFlags(c.Flags())
	return c
}

func main() {
	var c = newCommand()
	if err := c.Execute(); err != nil {
		os.Exit(1)
	}
}
