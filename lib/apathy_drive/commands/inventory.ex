defmodule ApathyDrive.Commands.Inventory do
  use ApathyDrive.Command
  alias ApathyDrive.{Character, Currency, Item, Mobile}

  def keywords, do: ["i", "inv", "inventory"]

  def execute(
        %Room{} = room,
        %Character{equipment: equipment, inventory: inventory} = character,
        _args
      ) do
    if equipment |> Enum.any?() do
      Mobile.send_scroll(
        character,
        "<p><span class='dark-yellow'>You are equipped with:</span></p><br>"
      )

      equipment
      |> Enum.each(fn item ->
        worn_on =
          if item.type == "Light" do
            String.pad_trailing("(Readied/#{item.uses})", 15)
          else
            String.pad_trailing("(#{item.worn_on})", 15)
          end

        Mobile.send_scroll(
          character,
          "<p><span class='dark-cyan'>#{worn_on}</span><span class='dark-green'>#{
            Item.colored_name(item, character: character)
          }</span></p>"
        )
      end)

      Mobile.send_scroll(character, "<br>")
    end

    keys = Enum.filter(inventory, &(&1.type == "Key"))

    inventory = inventory -- keys

    item_names = inventory |> Enum.map(&Item.colored_name(&1))

    item_names = Currency.to_list(character) ++ item_names

    if item_names |> Enum.count() > 0 do
      Mobile.send_scroll(character, "<p>You are carrying #{item_names |> to_sentence()}.</p>")
    else
      Mobile.send_scroll(character, "<p>You are carrying nothing.</p>")
    end

    if Enum.any?(keys) do
      Mobile.send_scroll(
        character,
        "<p>You have the following keys: #{Enum.map(keys, & &1.name) |> to_sentence()}</p>"
      )
    end

    mats = Map.values(character.materials)

    if Enum.any?(mats) do
      Mobile.send_scroll(
        character,
        "<p>You have the following crafting materials: #{
          Enum.map(mats, &(to_string(&1.amount) <> " " <> &1.material.name)) |> to_sentence()
        }</p>"
      )
    end

    Mobile.send_scroll(
      character,
      "<p><span class='dark-green'>Wealth:</span> <span class='dark-cyan'>#{
        Currency.wealth(character)
      } copper farthings</span></p>"
    )

    current_encumbrance = Character.encumbrance(character)
    max_encumbrance = Character.max_encumbrance(character)

    encumbrance_percent = trunc(current_encumbrance / max_encumbrance * 100)

    encumbrance =
      cond do
        encumbrance_percent < 17 ->
          "None [#{encumbrance_percent}%]"

        encumbrance_percent < 34 ->
          "<span class='dark-green'>Light [#{encumbrance_percent}%]</span>"

        encumbrance_percent < 67 ->
          "<span class='dark-yellow'>Medium [#{encumbrance_percent}%]</span>"

        :else ->
          "<span class='dark-red'>Heavy [#{encumbrance_percent}%]</span>"
      end

    Mobile.send_scroll(
      character,
      "<p><span class='dark-green'>Encumbrance:</span> <span class='dark-cyan'>#{
        current_encumbrance
      }/#{max_encumbrance} -</span> #{encumbrance}</p>"
    )

    room
  end

  def to_sentence(list) do
    list =
      list
      |> Enum.group_by(& &1)
      |> Map.values()
      |> Enum.map(fn items ->
        case length(items) do
          1 ->
            List.first(items)

          n ->
            "#{n} #{List.first(items)}"
        end
      end)

    case length(list) do
      0 ->
        ""

      1 ->
        List.first(list)

      2 ->
        Enum.join(list, " and ")

      _ ->
        {last, list} = List.pop_at(list, -1)
        Enum.join(list, ", ") <> " and " <> last
    end
  end
end
