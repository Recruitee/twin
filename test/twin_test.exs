defmodule TwinTest do
  use ExUnit.Case, async: true

  defmodule Dep do
    def one, do: 1
    def two, do: 2
    def nop, do: 0

    def id(n), do: n
  end

  defmodule App do
    @dep Twin.get(Dep)

    def run, do: @dep.one + @dep.two
    def id(n), do: @dep.id(n)
  end

  import Twin

  test "default - passthrough" do
    assert App.run == 3
  end

  test "stub return value once" do
    stub(Dep, :one, 10)

    assert App.run == 12
    assert App.run == 3

    assert_called Dep, :one
  end

  test "stub multiple return values" do
    Dep
    |> stub(:one, 10)
    |> stub(:two, 20)

    assert App.run == 30
    assert App.run == 3
  end

  test "stub multiple return values for the same function" do
    Dep
    |> stub(:one, 10)
    |> stub(:one, 20)

    assert App.run == 12
    assert App.run == 22
  end

  test "track dependency calls" do
    App.run

    assert_called Dep, :one
    assert_called Dep, :two
    refute_called Dep, :nop
  end

  test "track dependency calls with arguments" do
    App.id(1)

    assert_called Dep, :id, [1]
    refute_called Dep, :id, [2]

    App.id(2)

    assert_called Dep, :id, [2]
  end

  test "verify stubs when not called" do
    verify_stubs()
  end

  test "verify stubs when called" do
    stub(Dep, :one, 10)
    App.run
    verify_stubs()
  end

  test "keep stub local to current process" do
    out = self()
    {pid, ref} = spawn_monitor fn ->
      # 1. Mock inside process
      stub(Dep, :one, 5)

      # 2. Notify outer process that mock has been set
      send out, :ready

      # wait for message to execute mock
      assert_receive :go
      assert App.run == 7
    end

    # wait for ready message
    assert_receive :ready

    # change the mock - should have no effect
    stub(Dep, :one, 0)

    send pid, :go
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
  end

  test "stub for other pid" do
    {pid, ref} = spawn_monitor fn ->
      assert_receive :go
      assert App.run == 7
    end

    stub(pid, Dep, :one, 5)

    send pid, :go
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
  end
end
