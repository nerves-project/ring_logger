defmodule RingLogger.CircularBuffer do
  @moduledoc """
  Circular Buffer

  This is a modified version of https://github.com/keathley/circular_buffer
  that doesn't use `:queue`. It creates less garbage than the `:queue` version
  and is slightly faster in trivial benchmarks. RingLogger currently has other
  limitations that make it hard to see these improvements.

  When creating a circular buffer you must specify the max size:

  ```
  cb = CircularBuffer.new(10)
  ```
  """

  # How does this work?
  #
  # There are two lists, `a` and `b`. New items are placed into list `a`. Old
  # items are removed from list `b`.
  #
  # List `a` is ordered from newest to oldest, and list `b` is ordered from
  # oldest to newest. Everything in list `a` is newer than list `b`.
  #
  # When the circular buffer is full, the normal case, inserting an
  # item involves prepending it to `a` and removing the first item
  # in list `b`. The list ordering makes these both O(1).
  #
  # When no more items can be removed from list `b`, list `a` is
  # reversed and becomes the new list `b`.
  #
  # The functions for getting the oldest and newest items are also
  # fast: The oldest item is the head of list `b`. The newest item
  # is the head of list `a`.

  defstruct [:a, :b, :max_size, :count]

  alias __MODULE__, as: CB

  @doc """
  Creates a new circular buffer with a given size.
  """
  def new(size) when is_integer(size) and size > 0 do
    %CB{a: [], b: [], max_size: size, count: 0}
  end

  @doc """
  Inserts a new item into the next location of the circular buffer

  Amortized run time: O(1)
  Worst case run time: O(n)
  """
  def insert(%CB{b: b} = cb, item) when b != [] do
    %CB{cb | a: [item | cb.a], b: tl(b)}
  end

  def insert(%CB{count: count, max_size: max_size} = cb, item) when count < max_size do
    %CB{cb | a: [item | cb.a], count: cb.count + 1}
  end

  def insert(%CB{b: []} = cb, item) do
    new_b = cb.a |> Enum.reverse() |> tl()
    %CB{cb | a: [item], b: new_b}
  end

  @doc """
  Converts a circular buffer to a list.

  The list is ordered from oldest to newest elements based on their insertion
  order.

  Worst case run time: O(n)
  """
  def to_list(%CB{} = cb) do
    cb.b ++ Enum.reverse(cb.a)
  end

  @doc """
  Returns the newest element in the buffer

  Runs in constant time.
  """
  def newest(%CB{a: [newest | _rest]}), do: newest
  def newest(%CB{b: []}), do: nil

  @doc """
  Returns the oldest element in the buffer

  Mostly runs in constant time. Worst case O(n).
  """
  def oldest(%CB{b: [oldest | _rest]}), do: oldest
  def oldest(%CB{a: a}), do: List.last(a)

  @doc """
  Checks the buffer to see if its empty

  Runs in constant time
  """
  def empty?(%CB{} = cb) do
    cb.count == 0
  end

  defimpl Enumerable do
    def count(cb) do
      {:ok, cb.count}
    end

    def member?(cb, element) do
      {:ok, Enum.member?(cb.a, element) or Enum.member?(cb.b, element)}
    end

    def reduce(cb, acc, fun) do
      Enumerable.List.reduce(CB.to_list(cb), acc, fun)
    end

    def slice(_cb) do
      {:error, __MODULE__}
    end
  end

  defimpl Collectable do
    def into(original) do
      collector_fn = fn
        cb, {:cont, elem} -> CB.insert(cb, elem)
        cb, :done -> cb
        _cb, :halt -> :ok
      end

      {original, collector_fn}
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(cb, opts) do
      concat(["#CircularBuffer<", to_doc(CB.to_list(cb), opts), ">"])
    end
  end
end
