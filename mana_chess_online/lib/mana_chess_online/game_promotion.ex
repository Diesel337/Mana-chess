defmodule ManaChessOnline.GamePromotion do
  @moduledoc false

  def choice("Q", :white), do: "Q"
  def choice("R", :white), do: "R"
  def choice("B", :white), do: "B"
  def choice("N", :white), do: "N"
  def choice("Q", :black), do: "q"
  def choice("R", :black), do: "r"
  def choice("B", :black), do: "b"
  def choice("N", :black), do: "n"
  def choice(_choice, :white), do: "Q"
  def choice(_choice, :black), do: "q"
end
