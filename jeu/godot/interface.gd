extends CanvasLayer
##
## Tout ce que le joueur lit par-dessus la scène.
##
## Cela tenait dans une fonction de deux cent soixante-quinze lignes au milieu
## du jeu, et quatorze éléments d'interface y étaient manipulés directement
## depuis la logique — deux cent trente fois. Chaque écran à venir aurait ajouté
## sa part au même endroit.
##
## Le jeu ne connaît plus que les verbes ci-dessous. Il dit ce qu'il veut
## montrer ; où et comment cela s'affiche ne le regarde pas.

const PORTRAIT := 84          ## côté du visage dans la boîte de dialogue
const VISAGE_CODEX := 96      ## le même visage, à la taille d'une fiche
const COLONNE_CODEX := 170    ## largeur de la colonne des noms
const LIGNES_CODEX := 13      ## fiches visibles d'un coup dans la colonne

var _cadre: Panel
var _texte: RichTextLabel
var _visage: TextureRect
var _bandeau: Panel
var _recit: RichTextLabel
var _invite: Label
var _objectif: Label
var _ouverture: Panel
var _acheve: Panel
var _defaite: Panel
var _pause: Panel
var _menu: RichTextLabel
var _codex: Panel
var _codex_entete: RichTextLabel
var _codex_liste: RichTextLabel
var _codex_visage: TextureRect
var _codex_nom: RichTextLabel
var _codex_role: RichTextLabel
var _jauge_vie: ColorRect
var _jauge_energie: ColorRect
## Ce qui se dessine par-dessus la scène et doit céder la place au Codex.
var _hud: Array[Control] = []


func _ready() -> void:
	_batir()


func _batir() -> void:

	_cadre = Panel.new()
	_cadre.anchor_right = 1.0
	_cadre.anchor_top = 1.0
	_cadre.anchor_bottom = 1.0
	_cadre.offset_left = 16
	_cadre.offset_right = -16
	_cadre.offset_top = -120
	_cadre.offset_bottom = -16

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b0a10")
	style.border_color = Color("#c08f34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(10)
	_cadre.add_theme_stylebox_override("panel", style)
	_cadre.visible = false
	add_child(_cadre)

	## Le visage de qui parle, à gauche du cadre.
	##
	## Il tient dans la hauteur du cadre et garde ses proportions ; le texte
	## commence après lui. Un personnage sans portrait n'en laisse pas la place
	## vide : le cadre se referme sur le texte seul.
	_visage = TextureRect.new()
	_visage.anchor_bottom = 1.0
	_visage.offset_left = 6
	_visage.offset_top = 6
	_visage.offset_right = 6 + PORTRAIT
	_visage.offset_bottom = -6
	_visage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_visage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visage.visible = false
	_cadre.add_child(_visage)

	_texte = RichTextLabel.new()
	_texte.bbcode_enabled = true
	_texte.anchor_right = 1.0
	_texte.anchor_bottom = 1.0
	_texte.offset_left = 10
	_texte.offset_top = 8
	_texte.offset_right = -10
	_texte.offset_bottom = -8
	# Douze pixels dans une fenêtre qui en fait 270 de haut. À quinze, la
	# réplique débordait et Godot ajoutait une barre de défilement — une boîte de
	# dialogue qu'il faut faire défiler n'en est pas une.
	_texte.add_theme_font_size_override("normal_font_size", 15)
	_texte.add_theme_font_size_override("bold_font_size", 15)
	_texte.scroll_active = false
	_cadre.add_child(_texte)

	## L'invite se range dans le coin.
	##
	## Au milieu de l'écran elle se posait sur la scène, juste au-dessus du
	## cadre, et attirait l'œil là où il n'y avait rien à voir. Un rappel de
	## touche n'a pas à disputer le centre au décor.
	_invite = Label.new()
	_invite.text = "Espace"
	_invite.anchor_left = 1.0
	_invite.anchor_right = 1.0
	_invite.anchor_top = 1.0
	_invite.anchor_bottom = 1.0
	_invite.offset_left = -112
	_invite.offset_right = -16
	_invite.offset_top = -34
	_invite.offset_bottom = -10
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_invite.add_theme_color_override("font_color", Color("#f0d174"))
	_invite.add_theme_font_size_override("font_size", 14)
	_invite.visible = false
	add_child(_invite)

	## Le bandeau des descriptions.
	##
	## Ce qu'on lit n'est pas ce qu'on entend. La parole garde le cadre du bas,
	## bordé d'or, avec le nom de qui parle ; la description prend un bandeau
	## large, sans bordure ni nom, en italique et en argent — la couleur du
	## narrateur, non celle d'une voix. Les deux ne peuvent plus se confondre,
	## et les maladresses des personnages redeviennent audibles comme telles.
	_bandeau = Panel.new()
	_bandeau.anchor_right = 1.0
	_bandeau.anchor_top = 0.5
	_bandeau.anchor_bottom = 0.5
	_bandeau.offset_left = 0
	_bandeau.offset_right = 0
	_bandeau.offset_top = -46
	_bandeau.offset_bottom = 46
	var voile := StyleBoxFlat.new()
	voile.bg_color = Color(0.043, 0.039, 0.063, 0.88)
	voile.border_color = Color("#71727e")
	voile.border_width_top = 1
	voile.border_width_bottom = 1
	voile.set_content_margin_all(10)
	_bandeau.add_theme_stylebox_override("panel", voile)
	_bandeau.visible = false
	add_child(_bandeau)

	## Le texte se centre verticalement dans son bandeau.
	##
	## Une RichTextLabel n'a pas d'alignement vertical : étirée sur toute la
	## hauteur, elle colle son texte en haut et laisse un vide dessous, d'autant
	## plus visible qu'une description tient souvent sur une seule ligne. Un
	## CenterContainer, avec une étiquette qui se dimensionne à son contenu,
	## règle ce que l'ancrage ne sait pas exprimer.
	var centreur := CenterContainer.new()
	centreur.anchor_right = 1.0
	centreur.anchor_bottom = 1.0
	centreur.offset_left = 24
	centreur.offset_right = -24
	_bandeau.add_child(centreur)

	_recit = RichTextLabel.new()
	_recit.bbcode_enabled = true
	_recit.fit_content = true
	_recit.custom_minimum_size = Vector2(560, 0)
	_recit.scroll_active = false
	_recit.add_theme_font_size_override("normal_font_size", 15)
	_recit.add_theme_font_size_override("italics_font_size", 15)
	centreur.add_child(_recit)

	# L'objectif reste affiché : sans lui, un chapitre en quatre temps se joue à
	# tâtons, et le joueur croit que le jeu ne réagit pas alors qu'il attend.
	## Le menu de pause.
	##
	## Trois choix seulement : reprendre, noter où l'on en est, revenir au
	## titre. Le jeu note déjà la fin de chaque chapitre ; « sauvegarder » sert
	## à ne pas perdre un chapitre entamé quand on s'arrête au milieu.
	_pause = Panel.new()
	_pause.anchor_left = 0.5
	_pause.anchor_right = 0.5
	_pause.anchor_top = 0.5
	_pause.anchor_bottom = 0.5
	_pause.offset_left = -150
	_pause.offset_right = 150
	_pause.offset_top = -80
	_pause.offset_bottom = 80
	var repos := StyleBoxFlat.new()
	repos.bg_color = Color("#0b0a10")
	repos.border_color = Color("#c08f34")
	repos.set_border_width_all(2)
	repos.set_content_margin_all(14)
	_pause.add_theme_stylebox_override("panel", repos)
	_pause.visible = false
	add_child(_pause)

	_menu = RichTextLabel.new()
	_menu.bbcode_enabled = true
	_menu.anchor_right = 1.0
	_menu.anchor_bottom = 1.0
	_menu.scroll_active = false
	_menu.add_theme_font_size_override("normal_font_size", 15)
	_menu.add_theme_font_size_override("bold_font_size", 15)
	_pause.add_child(_menu)

	_batir_le_codex()

	_objectif = Label.new()
	_objectif.anchor_right = 1.0
	_objectif.offset_left = 18
	_objectif.offset_top = 10
	_objectif.offset_right = -14
	_objectif.add_theme_color_override("font_color", Color("#f0d174"))
	_objectif.add_theme_color_override("font_shadow_color", Color("#0b0a10"))
	_objectif.add_theme_constant_override("shadow_offset_x", 1)
	_objectif.add_theme_constant_override("shadow_offset_y", 1)
	_objectif.add_theme_font_size_override("font_size", 15)
	add_child(_objectif)

	_jauge_vie = _jauge(8, Color("#8b2020"), Color("#d14545"))
	_jauge_energie = _jauge(22, Color("#23202e"), Color("#5b9bd8"))
	# Les creux, non les parts pleines : c'est eux que le Codex doit escamoter.
	_hud = [_jauge_vie.get_parent(), _jauge_energie.get_parent(), _objectif]

	## Le mot de défaite se range en bas.
	##
	## Centré, il se posait exactement sur le corps — la caméra suit Wellan, donc
	## le panneau masquait ce qu'il annonçait. On ne dit pas à quelqu'un qu'il
	## est tombé en lui cachant l'endroit où il gît.
	_defaite = Panel.new()
	_defaite.anchor_left = 0.5
	_defaite.anchor_right = 0.5
	_defaite.anchor_top = 1.0
	_defaite.anchor_bottom = 1.0
	_defaite.offset_left = -170
	_defaite.offset_right = 170
	_defaite.offset_top = -96
	_defaite.offset_bottom = -16
	var deuil := StyleBoxFlat.new()
	deuil.bg_color = Color("#0b0a10")
	deuil.border_color = Color("#8b2020")
	deuil.set_border_width_all(2)
	deuil.set_content_margin_all(10)
	_defaite.add_theme_stylebox_override("panel", deuil)
	_defaite.visible = false
	add_child(_defaite)

	## Le carton d'ouverture.
	##
	## Un joueur qui reprend sa partie après trois jours ne sait plus où il en
	## était. Le rang du chapitre et sa source le lui disent en une ligne, et
	## rendent visible que la campagne se suit dans un ordre.
	_ouverture = Panel.new()
	_ouverture.anchor_left = 0.5
	_ouverture.anchor_right = 0.5
	_ouverture.anchor_top = 0.5
	_ouverture.anchor_bottom = 0.5
	# Assez haut pour la source et l'invite. Au premier réglage le cadre faisait
	# cent pixels : la référence au tome débordait sur deux lignes et « Espace »
	# passait sous le bord. Rien ne mesure qu'un cadre est trop court.
	_ouverture.offset_left = -260
	_ouverture.offset_right = 260
	_ouverture.offset_top = -86
	_ouverture.offset_bottom = 86
	var cartouche := StyleBoxFlat.new()
	cartouche.bg_color = Color("#0b0a10")
	cartouche.border_color = Color("#c08f34")
	cartouche.set_border_width_all(2)
	cartouche.set_content_margin_all(12)
	_ouverture.add_theme_stylebox_override("panel", cartouche)
	_ouverture.visible = false
	add_child(_ouverture)

	var titre := RichTextLabel.new()
	titre.bbcode_enabled = true
	titre.anchor_right = 1.0
	titre.anchor_bottom = 1.0
	titre.scroll_active = false
	titre.add_theme_font_size_override("normal_font_size", 15)
	titre.add_theme_font_size_override("bold_font_size", 18)
	_ouverture.add_child(titre)

	## Le chapitre achevé s'annonce sans arrêter la partie.
	##
	## Un panneau au centre, qui prenait la main jusqu'à ce qu'on appuie,
	## coupait la salle au moment précis où l'on avait envie d'y traîner : les
	## répliques qu'aucun objectif n'exige se perdaient. Le mot passe donc en
	## bandeau haut, et c'est Entrée — non la touche de dialogue — qui appelle
	## le chapitre suivant. On peut rester aussi longtemps qu'on veut.
	_acheve = Panel.new()
	_acheve.anchor_left = 0.5
	_acheve.anchor_right = 0.5
	_acheve.offset_left = -200
	_acheve.offset_right = 200
	_acheve.offset_top = 10
	_acheve.offset_bottom = 62
	var laurier := StyleBoxFlat.new()
	laurier.bg_color = Color("#0b0a10")
	laurier.border_color = Color("#c08f34")
	laurier.set_border_width_all(2)
	laurier.set_content_margin_all(12)
	_acheve.add_theme_stylebox_override("panel", laurier)
	_acheve.visible = false
	add_child(_acheve)

	var fin_mot := Label.new()
	fin_mot.anchor_right = 1.0
	fin_mot.anchor_bottom = 1.0
	fin_mot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fin_mot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fin_mot.add_theme_color_override("font_color", Color("#f0d174"))
	fin_mot.add_theme_font_size_override("font_size", 12)
	_acheve.add_child(fin_mot)

	var mot := Label.new()
	mot.text = "Wellan tombe.\n\nEspace pour reprendre la ligne."
	mot.anchor_right = 1.0
	mot.anchor_bottom = 1.0
	mot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mot.add_theme_color_override("font_color", Color("#dddde4"))
	mot.add_theme_font_size_override("font_size", 12)
	_defaite.add_child(mot)


## Le Codex : la liste de ceux à qui l'on a parlé, et la fiche du choisi.
##
## Il occupe tout l'écran, contrairement au menu de pause : une colonne de noms
## et un visage ne tiennent pas dans un panneau de trois cents pixels, et la
## consultation n'est pas une hésitation d'une seconde entre trois verbes.
func _batir_le_codex() -> void:
	_codex = Panel.new()
	_codex.anchor_right = 1.0
	_codex.anchor_bottom = 1.0
	var reliure := StyleBoxFlat.new()
	reliure.bg_color = Color("#0b0a10")
	reliure.border_color = Color("#c08f34")
	reliure.set_border_width_all(2)
	reliure.set_content_margin_all(20)
	_codex.add_theme_stylebox_override("panel", reliure)
	_codex.visible = false
	add_child(_codex)

	_codex_entete = _bloc(14)
	_codex_entete.anchor_right = 1.0
	_codex_entete.offset_bottom = 22
	_codex.add_child(_codex_entete)

	_codex_liste = _bloc(13)
	_codex_liste.anchor_bottom = 1.0
	_codex_liste.offset_top = 30
	_codex_liste.offset_right = COLONNE_CODEX
	_codex.add_child(_codex_liste)

	# Un simple trait plutôt qu'un second panneau : deux bordures dorées côte à
	# côte se lisaient comme deux fenêtres empilées.
	var filet := ColorRect.new()
	filet.color = Color("#2a2733")
	filet.anchor_bottom = 1.0
	filet.offset_left = COLONNE_CODEX + 8
	filet.offset_right = COLONNE_CODEX + 9
	filet.offset_top = 30
	_codex.add_child(filet)

	var marge := COLONNE_CODEX + 22

	_codex_visage = TextureRect.new()
	_codex_visage.offset_left = marge
	_codex_visage.offset_top = 32
	_codex_visage.offset_right = marge + VISAGE_CODEX
	_codex_visage.offset_bottom = 32 + VISAGE_CODEX
	_codex_visage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_codex_visage.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_codex_visage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_codex.add_child(_codex_visage)

	_codex_nom = _bloc(15)
	_codex_nom.anchor_right = 1.0
	_codex_nom.offset_left = marge + VISAGE_CODEX + 12
	_codex_nom.offset_top = 34
	_codex_nom.offset_bottom = 34 + VISAGE_CODEX
	_codex.add_child(_codex_nom)

	# Le rôle et les liens dans un seul pavé : leur longueur varie d'une fiche à
	# l'autre, et deux blocs posés à des hauteurs fixes finissent par se
	# chevaucher sur la fiche la plus bavarde.
	_codex_role = _bloc(13)
	_codex_role.anchor_right = 1.0
	_codex_role.anchor_bottom = 1.0
	_codex_role.offset_left = marge
	_codex_role.offset_top = 32 + VISAGE_CODEX + 14
	_codex.add_child(_codex_role)


## Un pavé de texte enrichi, sans ascenseur : la mise en page vient du BBCode.
func _bloc(taille: int) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.scroll_active = false
	t.add_theme_font_size_override("normal_font_size", taille)
	t.add_theme_font_size_override("bold_font_size", taille + 1)
	t.add_theme_font_size_override("italics_font_size", taille)
	return t


## Une jauge d'état, dans le coin haut-droit.
func _jauge(haut: int, fond: Color, plein: Color) -> ColorRect:
	var creux := ColorRect.new()
	creux.color = fond.darkened(0.5)
	creux.anchor_left = 1.0
	creux.anchor_right = 1.0
	creux.offset_left = -94
	creux.offset_right = -14
	creux.offset_top = haut
	creux.offset_bottom = haut + 8
	add_child(creux)

	var part := ColorRect.new()
	part.color = plein
	part.anchor_right = 1.0
	part.anchor_bottom = 1.0
	creux.add_child(part)
	return part


# ── Ce que le jeu demande ─────────────────────────────────────────────────
#
# Un verbe par intention. La logique ne touche plus un seul widget : elle dit
# « montre cette parole », « ferme », « voici l'objectif », et l'interface
# décide du reste. C'est ce qui permettra d'ajouter un inventaire ou une carte
# sans revenir dans le jeu.

## Le rappel d'objectif, en haut à gauche.
func objectif(texte: String) -> void:
	_objectif.text = texte


## L'invite de touche, dans le coin.
func invite(montrer: bool) -> void:
	_invite.visible = montrer


## Une parole : un nom, un texte, et le visage de qui parle s'il en a un.
func parole(nom: String, texte: String, portrait := "") -> void:
	_bandeau.visible = false
	_cadre.visible = true
	if portrait == "":
		_visage.visible = false
		_texte.offset_left = 10
	else:
		_visage.texture = load("res://assets/" + portrait)
		_visage.visible = true
		_texte.offset_left = 10 + PORTRAIT + 8
	_texte.text = "[b][color=#f0d174]%s[/color][/b]\n%s" % [nom, texte]


## Une description : ce que le joueur constate, sans nom ni visage.
func recit(texte: String) -> void:
	_cadre.visible = false
	_bandeau.visible = true
	_recit.text = "[center][i][color=#dddde4]%s[/color][/i][/center]" % texte


func fermer_dialogue() -> void:
	_cadre.visible = false
	_bandeau.visible = false


## Les deux jauges du coin haut-droit.
func jauges(vie: int, vie_max: int, energie: float, energie_max: float) -> void:
	_jauge_vie.anchor_right = clampf(float(vie) / maxf(1.0, float(vie_max)), 0.0, 1.0)
	_jauge_energie.anchor_right = clampf(energie / maxf(1.0, energie_max), 0.0, 1.0)


## Le carton qui annonce un chapitre.
func carton(entete: String, titre: String) -> void:
	var mot: RichTextLabel = _ouverture.get_child(0)
	mot.text = "[center][font_size=14][color=#a6a8b2]%s[/color][/font_size]\n\n[b][color=#f0d174]%s[/color][/b]\n\n[font_size=14][color=#a6a8b2]Espace[/color][/font_size][/center]" % [entete, titre]
	_ouverture.visible = true


func fermer_carton() -> void:
	_ouverture.visible = false


func carton_visible() -> bool:
	return _ouverture.visible


## Le bandeau de fin de chapitre, qui n'arrête pas la partie.
func acheve(texte: String) -> void:
	var mot: Label = _acheve.get_child(0)
	mot.text = texte
	_acheve.visible = true


func masquer_acheve() -> void:
	_acheve.visible = false


func acheve_visible() -> bool:
	return _acheve.visible


## Ce que le bandeau de fin annonce, pour qui veut le relire.
func mot_acheve() -> String:
	return (_acheve.get_child(0) as Label).text


## Le texte d'objectif affiché.
func objectif_affiche() -> String:
	return _objectif.text


## Une description est-elle à l'écran ?
func recit_visible() -> bool:
	return _bandeau.visible


func defaite(montrer: bool) -> void:
	_defaite.visible = montrer


## Le menu de pause, et le choix qui y est visé.
func pause(ouverte: bool, choix := 0, options: Array = [], mot := "") -> void:
	_pause.visible = ouverte
	if not ouverte:
		return
	var lignes := PackedStringArray(["[center][color=#a6a8b2]Pause[/color][/center]", ""])
	for i in options.size():
		lignes.append("[center]%s[/center]" % (
			"[color=#f0d174]▸ %s ◂[/color]" % options[i] if i == choix
			else "[color=#71727e]%s[/color]" % options[i]))
	if mot != "":
		lignes.append("")
		lignes.append("[center][color=#43c47f]%s[/color][/center]" % mot)
	_menu.text = "\n".join(lignes)


## Le Codex : la liste des rencontres, et la fiche de celle qu'on regarde.
##
## Le jeu passe les fiches, le rang choisi et le nombre de personnages que le
## monde compte ; la fenêtre qui défile se calcule ici, parce que le nombre de
## lignes lisibles est une affaire de mise en page.
func codex(ouvert: bool, fiches: Array = [], choix := 0, total := 0) -> void:
	_codex.visible = ouvert
	# Jauges et objectif appartiennent à la salle : le recueil couvre l'écran,
	# et deux barres de vie flottant sur ses pages passeraient pour un défaut.
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	_codex_entete.text = "[b][color=#f0d174]Codex[/color][/b]   [color=#71727e]%s[/color]" % (
		"aucune rencontre sur %d" % total if fiches.is_empty()
		else "%d rencontre%s sur %d" % [
			fiches.size(), "s" if fiches.size() > 1 else "", total])

	if fiches.is_empty():
		_codex_liste.text = ""
		_codex_visage.texture = null
		_codex_nom.text = ""
		_codex_role.text = "[color=#71727e][i]Adressez la parole à ceux que vous croisez : chacun s'inscrit ici.[/i][/color]"
		return

	choix = clampi(choix, 0, fiches.size() - 1)
	# La fenêtre suit le choix sans le coller au bord : on garde du contexte
	# au-dessus et au-dessous tant qu'il y en a.
	var haut := clampi(choix - LIGNES_CODEX / 2, 0, maxi(0, fiches.size() - LIGNES_CODEX))
	var lignes := PackedStringArray()
	if haut > 0:
		lignes.append("[color=#43414d]   ↑ %d[/color]" % haut)
	for i in range(haut, mini(haut + LIGNES_CODEX, fiches.size())):
		var rang := "[color=#43414d]%03d[/color]" % int(fiches[i].get("rang", 0))
		var nom := str(fiches[i].get("nom", ""))
		lignes.append("[color=#f0d174]▸ %s %s[/color]" % [rang, nom] if i == choix
			else "  %s [color=#71727e]%s[/color]" % [rang, nom])
	var reste := fiches.size() - (haut + LIGNES_CODEX)
	if reste > 0:
		lignes.append("[color=#43414d]   ↓ %d[/color]" % reste)
	_codex_liste.text = "\n".join(lignes)

	var fiche: Dictionary = fiches[choix]
	var visage := str(fiche.get("portrait", ""))
	_codex_visage.texture = load("res://assets/" + visage) if visage != "" else null

	# Le rang dans le monde, pas dans la collection : le joueur voit ce qui lui
	# manque, comme dans un Pokédex.
	_codex_nom.text = "[color=#71727e]N° %03d[/color]\n[b][color=%s]%s[/color][/b]\n%s" % [
		int(fiche.get("rang", 0)), str(fiche.get("teinte", "#f0d174")),
		str(fiche.get("nom", "")), _tomes(fiche.get("tomes", []))]

	var pages := PackedStringArray(["[color=#dddde4]%s[/color]" % str(fiche.get("role", ""))])
	var liens: Array = fiche.get("liens", [])
	if not liens.is_empty():
		pages.append("")
		pages.append("[color=#c08f34]Liens[/color]")
		for lien in liens:
			pages.append("[color=#a6a8b2]%s[/color] [color=#71727e]— %s[/color]" % [
				str(lien.get("nom", "")), str(lien.get("nature", ""))])
	_codex_role.text = "\n".join(pages)


## « Tomes 1 à 44 » — les bornes suffisent, la liste ne tiendrait pas.
func _tomes(tomes: Array) -> String:
	if tomes.is_empty():
		return ""
	var a := int(tomes[0])
	var b := int(tomes[tomes.size() - 1])
	return "[color=#71727e]Tome %d[/color]" % a if a == b \
		else "[color=#71727e]Tomes %d à %d[/color]" % [a, b]


func codex_visible() -> bool:
	return _codex.visible
