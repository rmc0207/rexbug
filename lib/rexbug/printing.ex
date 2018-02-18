defmodule Rexbug.Printing do
  @moduledoc """
  Provides the print handler and helper functions for writing custom
  print handlers for `Rexbug`. You shouldn't need to use it directly
  unless you want to implement a print handler yourself.

  See `Rexbug.start/2` `print_fun` option for details.
  """

  alias Rexbug.Printing
  import Rexbug.Printing.Utils

  #===========================================================================
  # Helper Structs
  #===========================================================================

  defmodule MFA do
    @type t :: %__MODULE__{}

    defstruct [
      :m,
      :f,
      :a, # either args or arity
    ]

    def from_erl({m, f, a}) do
      %__MODULE__{m: m, f: f, a: a}
    end

    def from_erl(a) when is_atom(a) do
      a
    end


    def represent(a) when is_atom(a) do
      "(#{inspect(a)})"
    end

    def represent(%__MODULE__{m: m, f: f, a: a}) do
      mrep = case Atom.to_string(m) do
        "Elixir." <> rest -> rest
        erlang_module -> ":#{erlang_module}"
      end

      arep = if is_list(a) do
        middle = a
        |> Enum.map(&printing_inspect/1)
        |> Enum.join(", ")
        "(#{middle})"
      else
        "/#{a}"
      end

      "#{mrep}.#{f}#{arep}"
    end
  end

  defmodule Timestamp do
    @type t :: %__MODULE__{}
    defstruct ~w(hours minutes seconds us)a

    def from_erl({h, m, s, us}) do
      %__MODULE__{hours: h, minutes: m, seconds: s, us: us}
    end

    def represent(%__MODULE__{hours: h, minutes: m, seconds: s}) do
      "#{format_int(h)}:#{format_int(m)}:#{format_int(s)}"
    end

    defp format_int(i, length \\ 2) do
      i
      |> Integer.to_string()
      |> String.pad_leading(length, "0")
    end
  end

  #---------------------------------------------------------------------------
  # Received message types
  #---------------------------------------------------------------------------

  defmodule Call do
    @type t :: %__MODULE__{}
    defstruct ~w(mfa dump from_pid from_mfa time)a

    def represent(%__MODULE__{} = struct) do
      ts = Timestamp.represent(struct.time)
      pid = printing_inspect(struct.from_pid)
      from_mfa = MFA.represent(struct.from_mfa)
      mfa = MFA.represent(struct.mfa)
      maybe_stack = represent_stack(struct.dump)

      "# #{ts} #{pid} #{from_mfa}\n# #{mfa}#{maybe_stack}"
    end

    defp represent_stack(nil), do: ""
    defp represent_stack(""), do: ""
    defp represent_stack(dump) do
      dump
      |> Printing.extract_stack()
      |> Enum.map(fn(fun_rep) -> "\n#   #{fun_rep}" end)
      |> Enum.join("")
    end
  end

  defmodule Return do
    @type t :: %__MODULE__{}
    defstruct ~w(mfa return_value from_pid from_mfa time)a

    def represent(%__MODULE__{} = struct) do
      ts = Timestamp.represent(struct.time)
      pid = printing_inspect(struct.from_pid)
      from_mfa = MFA.represent(struct.from_mfa)
      mfa = MFA.represent(struct.mfa)
      retn = printing_inspect(struct.return_value)

      "# #{ts} #{pid} #{from_mfa}\n# #{mfa} -> #{retn}"
    end
  end

  defmodule Send do
    @type t :: %__MODULE__{}
    defstruct ~w(msg to_pid to_mfa from_pid from_mfa time)a

    def represent(%__MODULE__{} = struct) do
      ts = Timestamp.represent(struct.time)
      to_pid = printing_inspect(struct.to_pid)
      to_mfa = MFA.represent(struct.to_mfa)
      from_pid = printing_inspect(struct.from_pid)
      from_mfa = MFA.represent(struct.from_mfa)
      msg = printing_inspect(struct.msg)

      "# #{ts} #{from_pid} #{from_mfa}\n# #{to_pid} #{to_mfa} <<< #{msg}"
    end
  end

  defmodule Receive do
    @type t :: %__MODULE__{}
    defstruct ~w(msg to_pid to_mfa time)a

    def represent(%__MODULE__{} = struct) do
      ts = Timestamp.represent(struct.time)
      to_pid = printing_inspect(struct.to_pid)
      to_mfa = MFA.represent(struct.to_mfa)
      msg = printing_inspect(struct.msg)

      "# #{ts} #{to_pid} #{to_mfa}\n# <<< #{msg}"
    end
  end

  #===========================================================================
  # Public Functions
  #===========================================================================

  @doc """
  The default value for the `Rexbug.start/2` `print_fun` option. Prints out
  the tracing messages generated by `:redbug` in a nice Elixir format.
  """
  @spec print(tuple()) :: :ok
  def print(message) do
    IO.puts("\n" <> format(message))
  end


  @doc false
  def format(message) do
    message
    |> from_erl()
    |> represent()
  end


  @doc """
  Translates the `:redbug` tuples representing the tracing messages to
  Elixir structs.

  You can use it to implement your own custom `print_fun`.
  """
  @spec from_erl(tuple()) :: Printing.Call.t | Printing.Return.t | Printing.Send.t | Printing.Receive.t | term()
  def from_erl({:call, {mfa, dump}, {from_pid, from_mfa}, time}) do
    %Call{
      mfa: MFA.from_erl(mfa),
      dump: dump,
      from_pid: from_pid,
      from_mfa: MFA.from_erl(from_mfa),
      time: Timestamp.from_erl(time)
    }
  end

  def from_erl({:retn, {mfa, retn}, {from_pid, from_mfa}, time}) do
    %Return{
      mfa: MFA.from_erl(mfa),
      return_value: retn,
      from_pid: from_pid,
      from_mfa: MFA.from_erl(from_mfa),
      time: Timestamp.from_erl(time),
    }
  end

  def from_erl({:send, {msg, {to_pid, to_mfa}}, {from_pid, from_mfa}, time}) do
    %Send{
      msg: msg,
      to_pid: to_pid,
      to_mfa: MFA.from_erl(to_mfa),
      from_pid: from_pid,
      from_mfa: MFA.from_erl(from_mfa),
      time: Timestamp.from_erl(time),
    }
  end

  def from_erl({:recv, msg, {to_pid, to_mfa}, time}) do
    %Receive{
      msg: msg,
      to_pid: to_pid,
      to_mfa: MFA.from_erl(to_mfa),
      time: Timestamp.from_erl(time),
    }
  end

  # fallthrough so that you can use it indiscriminately
  def from_erl(message) do
    message
  end


  @doc false
  def represent(%mod{} = struct) when mod in [Call, Return, Send, Receive] do
    mod.represent(struct)
  end


  @doc """
  Extracts the call stack from `t:Rexbug.Printing.Call.t/0` `dump` field.

  **NOTE**: The `dump` field will contain call stack information only
  if you specify `" :: stack"` in `Rexbug.start/2`'s trace pattern,
  it will be nil or empty otherwise.
  """
  @spec extract_stack(String.t) :: [String.t]
  def extract_stack(dump) do
    String.split(dump, "\n")
    |> Enum.filter( &Regex.match?(~r/Return addr 0x|CP: 0x/, &1) )
    |> Enum.flat_map(&extract_function/1)
  end

  #===========================================================================
  # Internal Functions
  #===========================================================================

  defp extract_function(line) do
    case Regex.run(~r"^.+\((.+):(.+)/(\d+).+\)$", line, capture: :all_but_first) do
      [m, f, arity] ->
        m = translate_module_from_dump(m)
        f = strip_single_quotes(f)
        ["#{m}.#{f}/#{arity}"]
      nil ->
        []
    end
  end


  defp strip_single_quotes(str) do
    String.trim(str, "'")
  end


  defp translate_module_from_dump(module) do
    case strip_single_quotes(module) do
      "Elixir." <> rest ->
        rest
      erlang_module ->
        ":#{erlang_module}"
    end
  end

end
