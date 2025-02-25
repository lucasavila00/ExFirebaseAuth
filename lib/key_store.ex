defmodule ExFirebaseAuth.KeyStore do
  @moduledoc false

  use GenServer, restart: :transient

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: ExFirebaseAuth.KeyStore)
  end

  @spec key_store_fail_strategy :: :stop | :warn | :silent
  @doc ~S"""
  Returns the configured key_store_fail_strategy

  ## Examples

      iex> ExFirebaseAuth.Token.key_store_fail_strategy()
      :stop
  """
  def key_store_fail_strategy,
    do: Application.get_env(:ex_firebase_auth, :key_store_fail_strategy, :stop)

  def init(_) do
    find_or_create_ets_table()

    case ExFirebaseAuth.KeySource.fetch_certificates() do
      :error ->
        case key_store_fail_strategy() do
          :stop ->
            {:stop, "Initial certificate fetch failed"}

          :warn ->
            Logger.warn("Fetching firebase auth certificates failed. Retrying again shortly.")

            schedule_refresh(10)

            {:ok, %{}}

          :silent ->
            schedule_refresh(10)

            {:ok, %{}}
        end

      {:ok, data} ->
        store_data_to_ets(data)

        Logger.debug("Fetched initial firebase auth certificates.")

        schedule_refresh()

        {:ok, %{}}
    end
  end

  # When the refresh `info` is sent, we want to fetch the certificates
  def handle_info(:refresh, state) do
    case ExFirebaseAuth.KeySource.fetch_certificates() do
      # keep trying with a lower interval, until then keep the old state
      :error ->
        Logger.warn("Fetching firebase auth certificates failed, using old state and retrying...")
        schedule_refresh(10)

      # if everything went okay, refresh at the regular interval and store the returned keys in state
      {:ok, keys} ->
        store_data_to_ets(keys)

        Logger.debug("Fetched new firebase auth certificates.")
        schedule_refresh()
    end

    {:noreply, state}
  end

  def find_or_create_ets_table do
    case :ets.whereis(ExFirebaseAuth.KeyStore) do
      :undefined -> :ets.new(ExFirebaseAuth.KeyStore, [:set, :public, :named_table])
      table -> table
    end
  end

  defp store_data_to_ets(data) do
    data
    |> Enum.each(fn {key, value} ->
      :ets.insert(ExFirebaseAuth.KeyStore, {key, value})
    end)
  end

  defp schedule_refresh(after_s \\ 300) do
    Process.send_after(self(), :refresh, after_s * 1000)
  end
end
