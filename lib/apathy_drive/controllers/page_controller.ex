defmodule ApathyDrive.PageController do
  use Phoenix.Controller

  def index(conn, _params) do
    render conn, "index"
  end

  def game(conn, %{"id" => _id}) do
    render conn, "game", []
  end

  def game(conn, _params) do
    url = Systems.Login.create
    redirect conn, ApathyDrive.Router.game_path(:game, url)
  end
end