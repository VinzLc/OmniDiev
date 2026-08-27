extends Node2D
##
## L'écran-titre et le choix de la partie.
##
## Deux temps, comme les jeux dont on s'inspire : le titre sur son illustration,
## puis trois emplacements où l'on reprend ou l'on recommence. Le jeu lui-même
## est une autre scène ; celle-ci ne fait que décider laquelle des trois parties
## on va jouer, et l'écrire là où elle la trouvera.

const Partie := preload("res://partie.gd")
const Donnees := preload("res://donnees.gd")
const EMPLACEMENTS := Partie.EMPLACEMENTS

var _campagne: Dictionary
var _parties: Dictionary
var _choix := 0
var _au_titre := true

var _titre: CanvasLayer
var _liste: VBoxContainer
var _invite: Label


func _ready() -> void:
	_campagne = { "chapitres": Partie.campagne() }
	_parties = Partie.charger()

	# Le banc de test entre directement dans le jeu.
	#
	# L'écran-titre attend une touche que personne ne presse en capture : le
	# processus restait là, sans erreur ni sortie, jusqu'au délai d'attente. Un
	# test doit pouvoir traverser ce qui attend un joueur.
	var a := OS.get_cmdline_user_args()
	if (a.has("--capture") or a.has("--effets") or a.has("--scene")
			or OS.get_cmdline_args().has("--capture")) and not a.has("--capture-titre"):
		_commencer()
		return

	_batir()
	_rafraichir()

	if a.has("--capture-titre"):
		_capturer()


func _batir() -> void:
	var couche := CanvasLayer.new()
	add_child(couche)
	_titre = couche

	var fond := TextureRect.new()
	fond.texture = load("res://assets/ecran-titre.png")
	fond.anchor_right = 1.0
	fond.anchor_bottom = 1.0
	fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fond.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	couche.add_child(fond)

	# Un voile sombre : l'illustration est belle mais chargée, et le titre s'y
	# perdrait sans qu'on lui fasse de la place.
	var voile := ColorRect.new()
	voile.color = Color(0.043, 0.039, 0.063, 0.45)
	voile.anchor_right = 1.0
	voile.anchor_bottom = 1.0
	couche.add_child(voile)

	var enseigne := Label.new()
	enseigne.text = "L'ÉPOPÉE DE WELLAN"
	enseigne.anchor_right = 1.0
	enseigne.offset_top = 44
	enseigne.offset_bottom = 90
	enseigne.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enseigne.add_theme_font_size_override("font_size", 34)
	enseigne.add_theme_color_override("font_color", Color("#f0d174"))
	enseigne.add_theme_color_override("font_outline_color", Color("#0b0a10"))
	enseigne.add_theme_constant_override("outline_size", 6)
	couche.add_child(enseigne)

	var sous := Label.new()
	sous.text = "les Chevaliers d'Émeraude"
	sous.anchor_right = 1.0
	sous.offset_top = 86
	sous.offset_bottom = 108
	sous.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous.add_theme_font_size_override("font_size", 15)
	sous.add_theme_color_override("font_color", Color("#a6a8b2"))
	sous.add_theme_color_override("font_outline_color", Color("#0b0a10"))
	sous.add_theme_constant_override("outline_size", 4)
	couche.add_child(sous)

	_liste = VBoxContainer.new()
	_liste.anchor_left = 0.5
	_liste.anchor_right = 0.5
	_liste.offset_left = -170
	_liste.offset_right = 170
	_liste.offset_top = 150
	_liste.add_theme_constant_override("separation", 8)
	_liste.visible = false
	couche.add_child(_liste)

	for i in EMPLACEMENTS:
		var ligne := Panel.new()
		ligne.custom_minimum_size = Vector2(340, 46)
		var cadre := StyleBoxFlat.new()
		# Presque opaque : le château transparaissait derrière le troisième
		# emplacement et le texte s'y perdait.
		cadre.bg_color = Color(0.043, 0.039, 0.063, 0.96)
		cadre.border_color = Color("#71727e")
		cadre.set_border_width_all(2)
		cadre.set_content_margin_all(8)
		ligne.add_theme_stylebox_override("panel", cadre)
		_liste.add_child(ligne)

		var mot := RichTextLabel.new()
		mot.bbcode_enabled = true
		mot.anchor_right = 1.0
		mot.anchor_bottom = 1.0
		mot.scroll_active = false
		mot.add_theme_font_size_override("normal_font_size", 14)
		mot.add_theme_font_size_override("bold_font_size", 14)
		ligne.add_child(mot)

	_invite = Label.new()
	_invite.anchor_right = 1.0
	_invite.anchor_top = 1.0
	_invite.anchor_bottom = 1.0
	_invite.offset_top = -40
	_invite.offset_bottom = -16
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite.add_theme_font_size_override("font_size", 14)
	_invite.add_theme_color_override("font_color", Color("#a6a8b2"))
	_invite.add_theme_color_override("font_outline_color", Color("#0b0a10"))
	_invite.add_theme_constant_override("outline_size", 4)
	couche.add_child(_invite)


## Le titre d'un chapitre, pour dire où en est une partie.
func _titre_du_chapitre(id: String) -> String:
	return Partie.titre(id)


func _rang(id: String) -> int:
	return Partie.rang(id)


func _rafraichir() -> void:
	_liste.visible = not _au_titre
	_invite.text = "Espace" if _au_titre else "↑ ↓ choisir     Espace commencer     Retour arrière effacer"

	var suite: Array = _campagne.get("chapitres", [])
	for i in EMPLACEMENTS:
		var ligne: Panel = _liste.get_child(i)
		var mot: RichTextLabel = ligne.get_child(0)
		var p = (_parties.get("parties", []) as Array)[i]
		var vise := i == _choix

		var cadre: StyleBoxFlat = ligne.get_theme_stylebox("panel").duplicate()
		cadre.border_color = Color("#f0d174") if vise else Color("#71727e")
		cadre.set_border_width_all(2 if vise else 1)
		ligne.add_theme_stylebox_override("panel", cadre)

		var puce := "[color=#f0d174]▸[/color] " if vise else "  "
		if p == null:
			mot.text = "%s[color=#71727e]Emplacement %d — vide[/color]" % [puce, i + 1]
		else:
			var ch := str(p.get("chapitre", ""))
			mot.text = "%s[b][color=#f2f2f5]Emplacement %d[/color][/b]   [color=#a6a8b2]chapitre %d sur %d — %s[/color]" % [
				puce, i + 1, _rang(ch), suite.size(), _titre_du_chapitre(ch)]


func _unhandled_input(e: InputEvent) -> void:
	if _au_titre:
		if e.is_action_pressed("ui_accept"):
			_au_titre = false
			_rafraichir()
		return

	if e.is_action_pressed("ui_down"):
		_choix = (_choix + 1) % EMPLACEMENTS
		_rafraichir()
	elif e.is_action_pressed("ui_up"):
		_choix = (_choix + EMPLACEMENTS - 1) % EMPLACEMENTS
		_rafraichir()
	elif e.is_action_pressed("ui_text_backspace"):
		(_parties["parties"] as Array)[_choix] = null
		_ecrire()
		_rafraichir()
	elif e.is_action_pressed("ui_accept"):
		_commencer()


## Ouvre la partie choisie et passe la main au jeu.
func _commencer() -> void:
	var parties: Array = _parties["parties"]
	if parties[_choix] == null:
		var suite: Array = _campagne.get("chapitres", [])
		parties[_choix] = { "chapitre": str(suite[0]) if not suite.is_empty() else "i-01" }
	_parties["courante"] = _choix
	_ecrire()
	# Différé : changer de scène pendant que l'arbre ajoute encore ses enfants
	# fait râler le moteur, et le fera un jour échouer.
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


func _ecrire() -> void:
	Partie.enregistrer(_parties)


func _capturer() -> void:
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://capture-titre.png")
	print("TITRE affiché")

	_au_titre = false
	_rafraichir()
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://capture-parties.png")
	print("PARTIES : %d emplacements, choix %d" % [EMPLACEMENTS, _choix])
	get_tree().quit()
