defmodule SquidSonarExample.Workflows.ScheduledReconciliation do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :nightly_reconciliation do
      cron("0 2 * * *", timezone: "Etc/UTC")

      payload do
        field(:batch_size, :integer, default: 100)
      end
    end

    step(:reconcile_invoices, :log, message: "reconcile scheduled invoices")
    transition(:reconcile_invoices, on: :ok, to: :complete)
  end
end
