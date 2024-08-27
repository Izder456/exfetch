defmodule Exfetch.Manip do
  @mebibyte 1_048_576

  def bytes_to_mebibytes(bytes) when is_binary(bytes) do
    bytes
    |> String.trim()
    |> parse_number()
    |> Kernel./(@mebibyte)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp parse_number(string) do
    case Float.parse(string) do
      {float, _} -> float
      :error -> 
        case Integer.parse(string) do
          {integer, _} -> integer * 1.0
          :error -> 0.0
        end
    end
  end
end

defmodule Exfetch.Resource do
  import Exfetch.Manip

  def get_platform do
    release_file = "/etc/os-release"
    uname = uname("")

    name =
    if File.exists?(release_file) do
      scrape_file("PRETTY_NAME", release_file)
    else
      ""
    end

    "#{uname} #{name}"
  end

  def get_release do
    release_file = "/etc/os-release"
    platform = get_platform()

    kernel_version =
    if String.match?(platform, ~r/BSD/) do
      execute_command("sysctl -n kern.osrelease")
    else
      uname("-r")
    end

    if File.exists?(release_file) do
      distro_version = scrape_file("VERSION_ID", release_file)
      "#{kernel_version} #{distro_version}"
    else
      kernel_version
    end
  end

  def get_user, do: System.get_env("USER") || "Could not get $USER"

  def get_host, do: to_string(:inet.gethostname() |> elem(1))

  def get_shell do
    System.get_env("SHELL")
    |> case do
         nil -> "Could not get $SHELL"
         path -> Path.basename(path)
       end
  end

  def get_session do
    System.get_env("XDG_CURRENT_DESKTOP") ||
      System.get_env("DESKTOP_SESSION") ||
      System.get_env("GDMSESSION") || 
      "Unknown"
  end
  
  def get_memory do
    platform = get_platform()
    memory = cond do
      String.match?(platform, ~r/Linux/) ->
        {mem, 0} = System.cmd("sh", ["-c", "free -b | awk '/Mem/ {print $2}'"])
        mem
      String.match?(platform, ~r/BSD/) ->
        {mem, 0} = System.cmd("sysctl", ["-n", "hw.physmem"])
        mem
      true ->
        "0"
    end

    memory |> bytes_to_mebibytes
  end

  def get_memory_usage do
    platform = get_platform()
    used_memory = cond do
      String.match?(platform, ~r/Linux/) ->
        {mem, 0} = System.cmd("sh", ["-c", "free -b | awk '/Mem/ {print $3}'"])
        mem
      String.match?(platform, ~r/BSD/) ->
        {mem, 0} = System.cmd("sh", ["-c", "vmstat -s | awk '/pages active/ {printf \"%.2f\\n\", $1*4096}'"])
        mem
      true ->
        "0"
    end

    used_memory |> bytes_to_mebibytes
  end
  
  def get_cpu do
    platform = get_platform()
    cond do
      String.match?(platform, ~r/Linux/) ->
        {cpu, 0} = System.cmd("sh", ["-c", "lscpu | grep 'Model name'| cut -d : -f 2 | awk '{$1=$1}1'"])
        String.trim(cpu)
      String.match?(platform, ~r/BSD/) ->
        {cpu, 0} = System.cmd("sysctl", ["-n", "hw.model"])
        String.trim(cpu)
      true ->
        "Could not get CPU"
    end
  end

  defp scrape_file(query, file) do
    file
    |> File.stream!()
    |> Enum.find_value("", fn line ->
      if String.contains?(line, query) do
        line
        |> String.split("=", parts: 2)
        |> List.last()
        |> String.replace("\"", "")
        |> String.trim()
      end
    end)
  end

  defp uname(argument), do: execute_command("uname #{argument}")

  defp execute_command(command) do
    {output, 0} = System.cmd("sh", ["-c", command])
    String.trim(output)
  end
end

defmodule Exfetch.OptionHandler do
  defstruct lowercase: false, color: 4, ascii: "Tear", separator: " -> "

  def parse(args) do
    {options, _, _} = OptionParser.parse(args,
      switches: [
        lowercase: :boolean,
        separator: :string,
        color: :integer,
        ascii: :string,
        help: :boolean
      ],
      aliases: [l: :lowercase, s: :separator, c: :color, a: :ascii, h: :help]
    )

    case options do
      [help: true] -> 
        IO.puts(help_message())
        System.halt(0)
      _ -> 
        struct(__MODULE__, options)
        |> validate_options()
    end
  end

  defp validate_options(%__MODULE__{} = options) do
    options
    |> validate_color()
    |> validate_ascii()
  end

  defp validate_color(%__MODULE__{color: color} = options) when color in 0..7, do: options
  defp validate_color(_), do: raise(ArgumentError, "Invalid color (0-7)")

  defp validate_ascii(%__MODULE__{ascii: ascii} = options) when ascii in ["None", "Tear", "Linux", "OpenBSD", "NetBSD", "FreeBSD", "FreeBSDTrident", "GhostBSD", "GhostBSDGhost"], do: options
  defp validate_ascii(_), do: raise(ArgumentError, "Invalid ASCII art option")

  def help_message do
    colors = Enum.map_join(30..37, " ", &"\e[#{&1}m#{&1 - 30}\e[0m")
    """
    Usage: exfetch [options]

    -l, --lowercase         Use lowercase labels
    -s, --separator STRING  Separator [default = " -> "]
    -c, --color COLOR       Pick a color output [default = 4]
                            (#{colors})
    -a, --ascii ASCII       Choose ASCII art [default = Tear]
                            (None, Tear, Linux, OpenBSD, NetBSD, FreeBSD, FreeBSDTrident, GhostBSD, GhostBSDGhost)
    -h, --help              Show help
    """
  end
end

defmodule Exfetch.CLI do
  alias Exfetch.{Resource, OptionHandler}

  @ascii_art %{
    "None" => List.duplicate(" ", 7),
    "Tear" => [
      "         ",
      "    ,    ",
      "   / \\   ",
      "  /   \\  ",
      " |     | ",
      "  \\___/  ",
      "         ",
      "         ",
      "         "
    ],
    "Linux" => [
      "     ___     ",
      "    [..,|    ",
      "    [<> |    ",
      "   / __` \\   ",
      "  ( /  \\ {|  ",
      "  /\\ __)/,)  ",
      " (}\\____\\/   ",
      "             ",
      "             "
    ],
    "OpenBSD" => [
      "      _____      ",
      "    \\-     -/    ",
      " \\_/ .`  ,   \\   ",
      " | ,    , 0 0 |  ",
      " |_  <   }  3 }  ",
      " / \\`   . `  /   ",
      "    /-_____-\\    ",
      "                 ",
      "                 "
    ],
    "NetBSD" => [
      "                       ",
      " \\\\\\`-______,----__    ",
      "  \\\\  -  _  __,---\\`_  ",
      "   \\\\  ,  . \\`.____    ",
      "    \\\\-______,----\\`-  ",
      "     \\\\                ",
      "      \\\\               ",
      "       \\\\              ",
      "                       ",
      "                       "
    ],
    "FreeBSD" => [
      "                ",
      " /\\.-^^^^^-./\\  ",
      " \\_)       (_/  ",
      " |           |  ",
      " |           |  ",
      "  ;         ;   ",
      "   '-_____-'    ",
      "                ",
      "                "
    ],
    "FreeBSDTrident" => [
      "                ",
      " /\\.-^^^^^-./\\  ",
      " \\_)  ,.,  (_/  ",
      " |     W     |  ",
      " |     |     |  ",
      "  ;    |    ;   ",
      "   '-_____-'    ",
      "                ",
      "                "
    ],
    "GhostBSD" => [
      "            ",
      "    _____   ",
      "   / __  )  ",
      "  ( /_/ /   ",
      "  _\\_, /    ",
      " \\____/     ",
      "            ",
      "            ",
      "            "
    ],
    "GhostBSDGhost" => [
      "   _______   ",
      "  /       \\  ",
      "  | () () |  ",
      "  |       |  ",
      "  |   3   |  ",
      "  /       \\  ",
      "  ^^^^^^^^^  ",
      "              ",
      "              "
    ],
  }

  @colors Enum.map(30..37, &"\e[#{&1}m")
  @bold "\e[1m"
  @reset "\e[0m"

  def main(args) do
    options = OptionHandler.parse(args)

    resources = %{
      "user" => &Resource.get_user/0,
      "host" => &Resource.get_host/0,
      "shell" => &Resource.get_shell/0,
      "os" => &Resource.get_platform/0,
      "release" => &Resource.get_release/0,
      "cpu" => &Resource.get_cpu/0,
      "mem_usage" => &Resource.get_memory_usage/0,
      "mem" => &Resource.get_memory/0,
      "dewm" => &Resource.get_session/0
    }

    ##
    # Concurrency
    ##
    
    # Step 1: Spawn all tasks
    tasks = 
      resources
      |> Enum.map(fn {key, func} -> Task.async(fn -> {key, func.()} end) end)

    # Step 2: Await all tasks
    results = 
      tasks
      |> Enum.map(&Task.await/1)
      |> Enum.into(%{})

    labels = if options.lowercase, do: ~w(user os ver shell de/wm cpu mem), else: ~w(USER OS VER SHELL DE/WM CPU MEM)
    chosen_ascii = @ascii_art[options.ascii]
    max_label_width = Enum.map(labels, &String.length/1) |> Enum.max()

    output_lines = generate_output(chosen_ascii, labels, results, max_label_width, options)

    output_lines
    |> Enum.each(&IO.puts/1)

    IO.puts("")
  end

  defp generate_output(ascii, labels, results, max_width, options) do
    max_lines = max(length(ascii), 9)

    Enum.map(0..(max_lines - 1), fn index ->
      ascii_line = Enum.at(ascii, index, String.duplicate(" ", String.length(List.first(ascii))))
      info_line = format_info_line(index, labels, results, max_width, options)
      colorize(ascii_line, info_line, options.color)
    end)
  end

  defp format_info_line(index, labels, results, max_width, options) do
    case index do
      1 -> format_line(labels, 0, max_width, options, "#{results["user"]}@#{results["host"]}")
      2 -> format_line(labels, 1, max_width, options, results["os"])
      3 -> format_line(labels, 2, max_width, options, results["release"])
      4 -> format_line(labels, 3, max_width, options, results["shell"])
      5 -> format_line(labels, 4, max_width, options, results["dewm"])
      6 -> format_line(labels, 5, max_width, options, results["cpu"])
      7 -> format_line(labels, 6, max_width, options, "#{results["mem_usage"]} MiB / #{results["mem"]} MiB")
      _ -> ""
    end
  end

  defp format_line(labels, index, max_width, options, value) do
    label = Enum.at(labels, index)
    "#{@bold}#{Enum.at(@colors, options.color)}#{String.pad_trailing(label, max_width)}#{@reset}#{options.separator}#{value}"
  end

  defp colorize(ascii_line, info_line, color) do
    "#{Enum.at(@colors, color)}#{ascii_line}#{@reset}#{info_line}"
  end
end
