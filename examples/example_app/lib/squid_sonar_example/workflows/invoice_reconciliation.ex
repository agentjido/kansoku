defmodule SquidSonarExample.Workflows.InvoiceReconciliation do
  @moduledoc false

  use Squidie.Workflow

  workflow do
    trigger :invoice_reconciliation do
      manual()

      payload do
        field(:invoice_id, :string)
        field(:retry_count, :integer)
      end
    end

    step(:load_invoice, :log, message: "load invoice")
    transition(:load_invoice, on: :ok, to: :complete)
  end
end
