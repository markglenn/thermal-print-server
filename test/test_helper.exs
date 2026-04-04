{:ok, _} = Application.ensure_all_started(:thermal_print_server)
ExUnit.start(exclude: [:cups_integration, :external_api, :s3_integration])
