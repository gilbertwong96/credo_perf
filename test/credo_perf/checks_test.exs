defmodule CredoPerf.ChecksTest do
  use Credo.Test.Case

  alias CredoPerf.Check.Warning.{
    EtsTableWalkForEviction,
    ProcessDictionaryCacheInPlug,
    SplitCacheAdmission,
    SystemGetEnvOutsideConfig
  }

  @request_code """
  defmodule Sample.Request do
    def call(conn, _opts), do: System.get_env("SECRET")
  end
  """

  @config_code """
  defmodule Sample.Env do
    def get(name, default \\\\ nil), do: Application.get_env(:sample, name, default)
  end
  """

  @walk_code """
  defmodule Sample.Cache do
    def put(table, key, value), do: :ets.insert(table, {key, value})

    def oldest(table) do
      table
      |> :ets.tab2list()
      |> Enum.min_by(fn {_key, used} -> used end, fn -> nil end)
    end
  end
  """

  @indexed_code """
  defmodule Sample.Cache do
    def put_order(index, key), do: :ets.insert(index, {System.monotonic_time(), key})
    def oldest(index), do: :ets.first(index)
  end
  """

  @split_code """
  defmodule Sample.Cache do
    def put(table, counter, bytes, entry) do
      :ets.insert(table, entry)
      :counters.add(counter, 3, bytes)
    end
  end
  """

  @atomic_code """
  defmodule Sample.Cache do
    def put(table, counter, bytes, entry) do
      if :atomics.add_get(counter, 1, bytes) <= 1024 do
        :ets.insert(table, entry)
      else
        :atomics.sub(counter, 1, bytes)
      end
    end
  end
  """

  @plug_memo """
  defmodule Sample.Plug do
    def call(conn, _opts) do
      Process.put(:parsed, :ok)
      conn
    end
  end
  """

  @gen_server_only """
  defmodule Sample.Store do
    use GenServer
    def get(key), do: GenServer.call(__MODULE__, {:get, key})
    def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state, key), state}
  end
  """

  test "CP1001 flags System.get_env outside configuration files" do
    @request_code
    |> to_source_file("lib/sample/request.ex")
    |> run_check(SystemGetEnvOutsideConfig)
    |> assert_issue(fn issue -> assert issue.trigger == "System.get_env" end)
  end

  test "CP1001 exempts configuration files" do
    @config_code
    |> to_source_file("config/runtime.exs")
    |> run_check(SystemGetEnvOutsideConfig)
    |> refute_issues()
  end

  test "CP1002 flags a table walk inside an eviction function" do
    @walk_code
    |> to_source_file("lib/sample/cache.ex")
    |> run_check(EtsTableWalkForEviction)
    |> assert_issue(fn issue -> assert issue.trigger == ":ets.tab2list" end)
  end

  test "CP1002 accepts an ordered index" do
    @indexed_code
    |> to_source_file("lib/sample/cache.ex")
    |> run_check(EtsTableWalkForEviction)
    |> refute_issues()
  end

  test "CP1003 flags an insert followed by accounting" do
    @split_code
    |> to_source_file("lib/sample/cache.ex")
    |> run_check(SplitCacheAdmission)
    |> assert_issue(fn issue -> assert issue.trigger == ":ets.insert" end)
  end

  test "CP1003 accepts an atomic reservation" do
    @atomic_code
    |> to_source_file("lib/sample/cache.ex")
    |> run_check(SplitCacheAdmission)
    |> refute_issues()
  end

  test "CP1004 flags Process.put inside a Plug" do
    @plug_memo
    |> to_source_file("lib/sample/plug.ex")
    |> run_check(ProcessDictionaryCacheInPlug)
    |> assert_issue(fn issue -> assert issue.trigger == "Process.put" end)
  end

  test "CP1004 ignores a GenServer that keeps state properly" do
    @gen_server_only
    |> to_source_file("lib/sample/store.ex")
    |> run_check(ProcessDictionaryCacheInPlug)
    |> refute_issues()
  end
end
