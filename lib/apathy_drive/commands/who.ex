defmodule ApathyDrive.Commands.Who do
  use ApathyDrive.Command
  alias ApathyDrive.{Character, Directory, Mobile}

  def keywords, do: ["who"]

  def execute(%Room{} = room, %Character{} = character, _arguments) do
    Mobile.send_scroll(
      character,
      "<p><span class='yellow'>        Current Adventurers</span></p>"
    )

    Mobile.send_scroll(
      character,
      "<p><span class='dark-grey'>        ===================</span>\n\n</p>"
    )

    list =
      Directory.list_characters()
      |> Enum.sort()

    longest_name_length =
      list
      |> Enum.max_by(&String.length(&1.name))
      |> Map.get(:name)
      |> String.length()

    list
    |> Enum.sort_by(& &1.name)
    |> Enum.each(fn
      %{name: name, game: game} ->
        name = name |> String.pad_trailing(longest_name_length)

        Mobile.send_scroll(
          character,
          "<p>        <span class='dark-green'>#{name} -</span> <span class='dark-magenta'>Stranger</span> <span class='dark-green'>of</span> <span class='dark-yellow'>#{
            game
          }</span>"
        )

      %{name: name, title: title} ->
        alignment = "" |> String.pad_leading(7)
        name = name |> String.pad_trailing(longest_name_length)

        Mobile.send_scroll(
          character,
          "<p>#{alignment} <span class='dark-green'>#{name} - <span class='dark-magenta'>#{title}</span></p>"
        )
    end)

    room
  end
end
