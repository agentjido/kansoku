defmodule KansokuExample.Workflows.RecurringMonitor do
  @moduledoc false

  use Jizoku.Workflow

  workflow do
    version("v1")

    trigger :recurring_monitor do
      manual()

      payload do
        field(:cycle, :integer)
      end
    end

    step(:rollover, KansokuExample.Steps.Rollover)
    transition(:rollover, on: :ok, to: :complete)
  end
end
