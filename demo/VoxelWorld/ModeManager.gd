extends Node

# Ok, let's try get everything straight.  Here's a hierarchy of possible states
#
# Menu opened
#   * TitleScreen
#   * MultiplayerMenu
#   * LevelSelectMenu
#   * OptionsMenu
#   * CreditsScreen
#
# In-Game states
#   * Loading 
#       (if you try to play while a level is loading in the background, you wait at the loading screen until it's ready)
#       (or if in multiplayer and the level is changed while you are in-game)
#   * Playing
#   * Editor opened
#   * Paused (the pause menu is shown)
# 
# The game is always visible in the background, even when a menu is open.  
#
# Multiplayer might be tricky. E.g. the host changing level while you are loading the current one.  
#
# State management needs to be super-hygeinic. Remember the motto "Invalid states should be unrepresentable".  A pipe-dream for this project, but I want that level of tightness.


const MODE_GAME=0
const MODE_EDITOR=1

var mode : int = MODE_GAME

var editor_node:EditorUI
