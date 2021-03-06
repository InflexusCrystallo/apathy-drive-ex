defmodule ApathyDrive.Class do
  use Ecto.Schema
  import Ecto.Changeset
  alias ApathyDrive.{Class, Match, Repo}

  schema "classes" do
    field(:description, :string)
    field(:name, :string)
    field(:weapon, :string)
    field(:armour, :string)
    field(:combat_level, :integer)
    field(:stealth, :boolean)
    field(:exp_modifier, :integer)

    field(:spellcasting_attributes, :any, virtual: true)

    has_many(:classes_traits, ApathyDrive.ClassTrait)
    has_many(:traits, through: [:classes_traits, :trait])

    timestamps()
  end

  @weapons [
    "One Handed Blunt",
    "Two Handed Blunt",
    "One Handed Blade",
    "Two Handed Blade",
    "Any Blade",
    "Any Blunt",
    "Any One Handed",
    "Any Two Handed",
    "All",
    "Limited"
  ]

  @armours [
    "Natural",
    "Cloth",
    "Leather",
    "Mail",
    "Plate"
  ]

  @doc false
  def changeset(%Class{} = class, attrs \\ %{}) do
    class
    |> cast(attrs, [:name, :description, :weapon, :armour, :combat_level, :stealth, :exp_modifier])
    |> validate_required([
      :name,
      :description,
      :weapon,
      :armour,
      :combat_level,
      :stealth
    ])
    |> validate_inclusion(:weapon, @weapons)
    |> validate_inclusion(:armour, @armours)
    |> validate_inclusion(:combat_level, 1..5)
    |> cast_assoc(:classes_traits)
  end

  def select do
    Repo.all(__MODULE__, select: [:id, :name])
    |> Enum.map(&{&1.name, &1.id})
  end

  def all do
    Repo.all(__MODULE__, select: [:id, :name, :description])
  end

  def ids do
    Repo.all(__MODULE__, select: [:id])
    |> Enum.map(&Map.get(&1, :id))
  end

  def weapon_select do
    Enum.map(@weapons, &{&1, &1})
  end

  def armour_select do
    Enum.map(@armours, &{&1, &1})
  end

  def match_by_name(name) do
    races =
      __MODULE__
      |> ApathyDrive.Repo.all()

    Match.all(races, :keyword_starts_with, name)
  end
end
