extends CanvasLayer
##
## Les commandes du pouce.
##
## Le jeu se joue au clavier — ZQSD, J, K, Échap. Sur un téléphone il n'y a pas
## de clavier, et le jeu y était donc regardable mais pas jouable.
##
## Cette couche ne connaît rien du jeu et le jeu ne la connaît pas. Elle pousse
## des `InputEventAction` dans la file d'entrée : pour tout le reste du code,
## un pouce sur la croix est indistinguable d'un doigt sur la touche. C'est ce
## qui permet de l'ajouter sans toucher une ligne de la logique — ni au combat,
## ni aux menus, ni aux dialogues.
##
## Deux façons de lire une action coexistent dans le jeu, et il fallait servir
## les deux : le déplacement interroge `Input.get_vector()` à chaque image,
## tandis que les menus attendent un événement dans `_unhandled_input`.
## `parse_input_event()` satisfait les deux — il délivre l'événement *et* met à
## jour l'état de l'action. `Input.action_press()`, lui, n'aurait fait que le
## second, et les menus seraient restés sourds.

## Le côté d'une touche, en unités de la toile de 640×360.
##
## À cette échelle, quarante-six pixels font environ neuf millimètres sur un
## téléphone tenu en paysage — le minimum sous lequel le pouce rate sa cible.
const COTE := 46
const COTE_ACTION := 56
const MARGE := 12

const FOND := Color(0.04, 0.09, 0.07, 0.42)
const FOND_PRESSE := Color(0.24, 0.86, 0.59, 0.34)
const BORD := Color(0.24, 0.86, 0.59, 0.30)
const SIGNE := Color(0.91, 0.95, 0.93, 0.72)

var _racine: Control
## « jeu » porte tout ; « menu » ne garde que haut, bas et valider — un bouton
## « frapper » sur l'écran-titre n'aurait frappé personne.
var _mode := "jeu"


func _init(mode: String = "jeu") -> void:
	_mode = mode
	# Au-dessus de l'interface, qui est elle-même au-dessus de la scène : une
	# commande que le coffre à butin recouvre ne sert à rien.
	layer = 10


func _ready() -> void:
	# Sur un ordinateur, ces touches encombreraient l'écran sans rien apporter.
	# Le test vaut pour le web : un navigateur de téléphone répond oui, celui
	# d'un portable non.
	if not DisplayServer.is_touchscreen_available():
		hide()
		return
	_batir()


func _batir() -> void:
	_racine = Control.new()
	_racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Sans cela, le rectangle plein écran avalerait les touches destinées au
	# jeu : seuls les boutons doivent intercepter quoi que ce soit.
	_racine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_racine)

	var bas := 360 - MARGE - COTE
	var milieu := 360 - MARGE - COTE - COTE - 2
	var cx := MARGE + COTE + 2
	var dx := 640 - MARGE - COTE_ACTION

	# ── La croix, à gauche ────────────────────────────────────────────────
	# Disposée en losange plutôt qu'en carré plein : les diagonales ne servent
	# pas — le déplacement les compose depuis deux touches voisines.
	#
	# Les flèches sont dessinées, non écrites : « ▲ » manque à la police par
	# défaut de Godot et sortait en carré vide.
	_touche("", ["ui_up"], Vector2(cx, milieu - COTE - 2), COTE, Vector2.UP)
	_touche("", ["ui_down"], Vector2(cx, bas), COTE, Vector2.DOWN)
	if _mode == "jeu":
		_touche("", ["ui_left"], Vector2(MARGE, milieu), COTE, Vector2.LEFT)
		_touche("", ["ui_right"], Vector2(cx + COTE + 2, milieu), COTE, Vector2.RIGHT)

	# Un seul bouton pour valider. Il porte aussi « suivant », qui n'ouvre que
	# le chapitre d'après : deux boutons pour deux confirmations que le joueur
	# ne distingue pas auraient été deux occasions de se tromper.
	_touche("OK", ["ui_accept", "suivant"], Vector2(dx, bas - 4), COTE_ACTION)

	if _mode != "jeu":
		return

	# ── Les actions, à droite ─────────────────────────────────────────────
	_touche("J", ["frapper"], Vector2(dx, milieu - 6), COTE_ACTION)
	_touche("K", ["lancer"], Vector2(dx - COTE_ACTION - 6, bas - 4), COTE_ACTION)

	# ── Course et pause ───────────────────────────────────────────────────
	# Deux chevrons ASCII plutôt que « » » : même raison que les flèches.
	_touche(">>", ["courir"], Vector2(MARGE, milieu - COTE - 2), COTE - 10)
	# « pause » ouvre le menu, « ui_cancel » referme ce qui est ouvert : le même
	# geste doit faire les deux, sans quoi le pouce reste enfermé dans le sac.
	_touche("II", ["pause", "ui_cancel"], Vector2(640 - MARGE - 34, MARGE), 34)


## Une touche, et les actions qu'elle presse.
##
## `sens` non nul remplace le texte par une flèche dessinée.
func _touche(signe: String, actions: Array, ou: Vector2, cote: int,
		sens: Vector2 = Vector2.ZERO) -> void:
	var b := Button.new()
	b.text = signe
	b.position = ou
	b.size = Vector2(cote, cote)
	b.focus_mode = Control.FOCUS_NONE  # sinon la touche garde le focus et vole le clavier
	b.add_theme_font_size_override("font_size", 15 if cote > 40 else 12)
	b.add_theme_color_override("font_color", SIGNE)
	b.add_theme_color_override("font_pressed_color", SIGNE)
	b.add_theme_color_override("font_hover_color", SIGNE)
	b.add_theme_stylebox_override("normal", _fond(FOND, cote))
	b.add_theme_stylebox_override("hover", _fond(FOND, cote))
	b.add_theme_stylebox_override("pressed", _fond(FOND_PRESSE, cote))
	b.button_down.connect(_presser.bind(actions, true))
	b.button_up.connect(_presser.bind(actions, false))
	_racine.add_child(b)

	if sens != Vector2.ZERO:
		var f := Fleche.new()
		f.sens = sens
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Le triangle ne doit pas intercepter le doigt : c'est le bouton
		# dessous qui écoute.
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(f)


## Un triangle, faute de police qui en porte un.
class Fleche extends Control:
	var sens := Vector2.UP

	func _draw() -> void:
		var c := size / 2.0
		var r := size.x * 0.27
		var perp := Vector2(-sens.y, sens.x)
		draw_colored_polygon(PackedVector2Array([
			c + sens * r,
			c - sens * r * 0.75 + perp * r * 0.85,
			c - sens * r * 0.75 - perp * r * 0.85,
		]), Color(0.91, 0.95, 0.93, 0.72))


func _fond(couleur: Color, cote: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = couleur
	s.border_color = BORD
	s.set_border_width_all(1)
	s.set_corner_radius_all(cote / 2)
	return s


func _presser(actions: Array, presse: bool) -> void:
	for a in actions:
		if not InputMap.has_action(a):
			continue
		var e := InputEventAction.new()
		e.action = a
		e.pressed = presse
		# `get_vector()` lit la force, non le booléen : sans elle, la croix
		# donnait un déplacement de longueur nulle et Wellan ne bougeait pas.
		e.strength = 1.0 if presse else 0.0
		Input.parse_input_event(e)
