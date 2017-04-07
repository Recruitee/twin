defmodule TwinTest do
  use ExUnit.Case, async: true

  defmodule Dep do
    def one, do: 1
    def two, do: 2
    def nop, do: 0
  end

  defmodule App do
    @dep Twin.get(Dep)

    def run, do: @dep.one + @dep.two
  end

  test "default - passthrough" do
    assert App.run == 3
  end

  test "stub return value once" do
    Twin.stub(Dep, :one, 10)

    assert App.run == 12
    assert App.run == 3
  end

  test "stub multiple return values" do
    Dep
    |> Twin.stub(:one, 10)
    |> Twin.stub(:two, 20)

    assert App.run == 30
    assert App.run == 3
  end

  test "track dependency calls" do
    App.run

    assert Twin.called?(Dep, :one)
    assert Twin.called?(Dep, :two)
    refute Twin.called?(Dep, :nop)
  end

  test "keep stub local to current process" do
    out = self()
    {pid, ref} = spawn_monitor fn ->
      # 1. Mock inside process
      Twin.stub(Dep, :one, 5)

      # 2. Notify outer process that mock has been set
      send out, :ready

      # wait for message to execute mock
      assert_receive :go
      assert App.run == 7
    end

    # wait for ready message
    assert_receive :ready

    # change the mock - should have no effect
    Twin.stub(Dep, :one, 0)

    send pid, :go
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
  end

  test "stub for other pid" do
    {pid, ref} = spawn_monitor fn ->
      assert_receive :go
      assert App.run == 7
    end

    Twin.stub(pid, Dep, :one, 5)

    send pid, :go
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
  end
end
