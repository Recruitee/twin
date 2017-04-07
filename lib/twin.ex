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
  defmacro assert_called(mod, fun) do
    quote bind_quoted: [mod: mod, fun: fun] do
      assert Twin.called?(mod, fun)
    end
  end

  defmacro assert_called(mod, fun, args) do
    quote bind_quoted: [mod: mod, fun: fun, args: args] do
      assert Twin.called?(mod, fun, args)
    end
  end

  defmacro refute_called(mod, fun) do
    quote bind_quoted: [mod: mod, fun: fun] do
      refute Twin.called?(mod, fun)
    end
  end

  defmacro refute_called(mod, fun, args) do
    quote bind_quoted: [mod: mod, fun: fun, args: args] do
      refute Twin.called?(mod, fun, args)
    end
  end

  use GenServer

  ## CLIENT API

  def start_link,               do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def call(mod, fun, args),     do: GenServer.call(__MODULE__, {:call, {mod, fun, args}})
  def called?(mod, fun),        do: GenServer.call(__MODULE__, {:called?, {mod, fun}})
  def called?(mod, fun, args),  do: GenServer.call(__MODULE__, {:called?, {mod, fun, args}})

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
