defmodule Twin do
  @moduledoc """
  See http://teamon.eu/2017/different-approach-to-elixir-mocks-doubles/
  """

  ## PROXY

  defmodule Proxy do
    def unquote(:"$handle_undefined_function")(fun, args) do
      [{__MODULE__, mod} | rest] = Enum.reverse(args)
      Twin.call(mod, fun, Enum.reverse(rest))
    end
  end

  ## MACROS
  def assert_called(mod, fun) do
    ExUnit.Assertions.assert Twin.called?(mod, fun), "#{mod}.#{fun} was not called"
  end

  def assert_called(mod, fun, args) do
    ExUnit.Assertions.assert Twin.called?(mod, fun, args),
       "#{mod}.#{fun}(#{args |> Enum.map(&inspect/1) |> Enum.join(", ")}) was not called"
  end

  def refute_called(mod, fun) do
    ExUnit.Assertions.refute Twin.called?(mod, fun), "#{mod}.#{fun} was called"
  end

  def refute_called(mod, fun, args) do
    ExUnit.Assertions.refute Twin.called?(mod, fun, args),
      "#{mod}.#{fun}(#{args |> Enum.map(&inspect/1) |> Enum.join(", ")}) was called"
  end

  def verify_stubs do
    stubs = Twin.stubs
    ExUnit.Assertions.assert stubs == [],
      "Following stubs were not called:\n#{stubs |> Enum.map(&inspect/1) |> Enum.join("\n")}"
  end

  use GenServer

  ## CLIENT API

  def start_link,               do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def call(mod, fun, args),     do: GenServer.call(__MODULE__, {:call, {mod, fun, args}})
  def called?(mod, fun),        do: GenServer.call(__MODULE__, {:called?, {mod, fun}})
  def called?(mod, fun, args),  do: GenServer.call(__MODULE__, {:called?, {mod, fun, args}})
  def stubs(pid \\ self()),     do: GenServer.call(__MODULE__, {:stubs, pid})

  def stub(pid \\ self(), mod, fun, ret) do
    GenServer.call(__MODULE__, {:stub, pid, {mod, fun, ret}})
    mod
  end

  def get(mod) do
    case Mix.env do
      :test -> {Twin.Proxy, mod}
      _     -> mod
    end
  end

  ## CALLBACKS

  def init(_) do
    {:ok, %{}}
  end

  def handle_call({:call, mfa}, {pid, _}, state) do
    {ret, dict} = do_call(state[pid], mfa)
    {:reply, ret, Map.put(state, pid, dict)}
  end

  def handle_call({:stub, pid, mfr}, _, state) do
    dict = do_stub(state[pid], mfr)
    {:reply, :ok, Map.put(state, pid, dict)}
  end

  def handle_call({:called?, mfa}, {pid, _}, state) do
    {:reply, do_called?(state[pid], mfa), state}
  end

  def handle_call({:stubs, pid}, _, state) do
    {:reply, get_in(state, [pid, :stubs]) || [], state}
  end

  ## INTERNALS

  defp do_call(nil, {m,f,a} = mfa) do
    {apply(m,f,a), %{stubs: [], history: [mfa]}}
  end
  defp do_call(%{stubs: stubs, history: history}, {m,f,a} = mfa) do

    # check for stubs, else pass-through
    {ret, stubs} = case find_stub(stubs, {m,f}) do
      {nil, stubs} -> {apply(m,f,a), stubs}
      {ret, stubs} -> {ret, stubs}
    end

    # save call to history
    {ret, %{stubs: stubs, history: [mfa | history]}}
  end

  defp do_stub(nil, mfr), do: %{stubs: [mfr], history: []}
  defp do_stub(dict, mfr), do: %{dict | stubs: dict.stubs ++ [mfr]}

  defp do_called?(nil, _), do: false
  defp do_called?(%{history: history}, {m,f}), do: Enum.find(history, &match?({^m, ^f, _}, &1)) != nil
  defp do_called?(%{history: history}, {m,f,a}), do: Enum.find(history, &match?({^m, ^f, ^a}, &1)) != nil

  defp find_stub(xs, mf), do: find_stub(xs, mf, [])
  defp find_stub([], _, rest), do: {nil, Enum.reverse(rest)}
  defp find_stub([{m,f,r} | xs], {m,f}, rest), do: {r, Enum.reverse(rest) ++ xs}
  defp find_stub([x | xs], mf, rest), do: find_stub(xs, mf, [x | rest])
end
