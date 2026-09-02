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
const COLONNE_CHAPITRE := 250  ## un titre de chapitre est une phrase, non un nom
const LIGNES_CODEX := 13      ## fiches visibles d'un coup dans la colonne

var _cadre: Panel
var _texte: RichTextLabel
var _visage: TextureRect
var _bandeau: Panel
var _recit: RichTextLabel
var _invite: Label
var _objectif: Label
var _lieu: Label
var _fondu: Tween
var _avis: Label
var _fondu_avis: Tween
var _commandes: Panel
var _commandes_texte: RichTextLabel
var _sac: Panel
var _sac_entete: RichTextLabel
var _sac_liste: RichTextLabel
var _sac_texte: RichTextLabel
var _sac_icone: TextureRect
var _sac_stats: RichTextLabel
## La vue d'équipement : Wellan de face, et ce qu'il porte autour de lui.
var _sac_doll: TextureRect
var _sac_cases := {}          ## par emplacement : { cadre, image, nom }
## Le coffre ouvert : ce qu'il contient, en cases qu'on survole.
signal butin_survole(rang: int)
signal butin_pris()

var _butin: Panel
var _butin_entete: RichTextLabel
var _butin_texte: RichTextLabel
var _butin_cases: Array[Panel] = []
var _carte: Panel
var _carte_texte: RichTextLabel
var _carte_marques: Array[Control] = []
var _carte_curseur: ColorRect
var _chapitres: Panel
var _chapitres_entete: RichTextLabel
var _chapitres_liste: RichTextLabel
var _chapitres_texte: RichTextLabel
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
	_invite.text = "Espace"        ## remplacé par le nom d'une porte quand on en longe une
	_invite.anchor_left = 1.0
	_invite.anchor_right = 1.0
	_invite.anchor_top = 1.0
	_invite.anchor_bottom = 1.0
	# Assez large pour un nom de salle suivi du rappel de touche : « Espace »
	# seul tenait dans quatre-vingt-seize pixels, « La bibliothèque d'Élund ›
	# Espace » y perdait sa fin. Le texte reste calé à droite, donc rien ne
	# bouge tant qu'il est court.
	_invite.offset_left = -300
	_invite.offset_right = -16
	_invite.offset_top = -34
	_invite.offset_bottom = -10
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_invite.add_theme_color_override("font_color", Color("#f0d174"))
	_invite.add_theme_font_size_override("font_size", 14)
	_invite.visible = false
	add_child(_invite)

	## Le nom de la salle où l'on entre.
	##
	## Il paraît le temps qu'on le lise, puis s'efface. Un nom qui reste devient
	## un élément d'interface de plus, et l'œil cesse de le voir ; un décor qui
	## ne se nomme jamais reste un couloir entre deux dialogues.
	##
	## Sous l'objectif, non à côté : les deux sont en haut, et se disputer la
	## même ligne les rendrait illisibles tous les deux.
	_lieu = Label.new()
	_lieu.anchor_right = 1.0
	_lieu.offset_left = 18
	_lieu.offset_top = 32
	_lieu.offset_right = -14
	_lieu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lieu.add_theme_color_override("font_color", Color("#dddde4"))
	_lieu.add_theme_color_override("font_shadow_color", Color("#0b0a10"))
	_lieu.add_theme_constant_override("shadow_offset_x", 1)
	_lieu.add_theme_constant_override("shadow_offset_y", 1)
	_lieu.add_theme_font_size_override("font_size", 17)
	_lieu.modulate = Color(1, 1, 1, 0)
	add_child(_lieu)

	## L'avis : ce que le jeu vient d'ajouter sans qu'on l'ait demandé.
	##
	## En bas à gauche, juste au-dessus du cadre de dialogue. Le haut est déjà
	## pris par l'objectif et le nom du lieu ; un troisième bandeau là-haut ne se
	## lirait plus, et celui-ci paraît au moment précis où l'on regarde quelqu'un
	## en face de soi.
	_avis = Label.new()
	_avis.anchor_top = 1.0
	_avis.anchor_bottom = 1.0
	_avis.offset_left = 18
	_avis.offset_right = 400
	_avis.offset_top = -146
	_avis.offset_bottom = -124
	_avis.add_theme_color_override("font_color", Color("#8fd39b"))
	_avis.add_theme_color_override("font_shadow_color", Color("#0b0a10"))
	_avis.add_theme_constant_override("shadow_offset_x", 1)
	_avis.add_theme_constant_override("shadow_offset_y", 1)
	_avis.add_theme_font_size_override("font_size", 15)
	_avis.modulate = Color(1, 1, 1, 0)
	add_child(_avis)

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
	# La hauteur se pose ici pour un cadre vide ; `pause()` la reprend d'après
	# le nombre d'entrées. Fixée à cent soixante pixels, elle tenait quatre
	# lignes — et le jour où le menu en a compté sept, « Sauvegarder » et
	# « Écran-titre » sont sortis du cadre sans que rien ne le signale. Un
	# panneau se mesure à ce qu'il contient.
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
	_hud = [_jauge_vie.get_parent(), _jauge_energie.get_parent(), _objectif, _lieu, _avis, _invite]

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

	_batir_le_sac()
	_batir_les_chapitres()
	_batir_la_carte()
	_batir_le_butin()

	# En tout dernier, et c'est la seule chose qui compte dans son placement.
	#
	# Un `Control` ne participe pas au tri par profondeur : il se dessine dans
	# l'ordre de l'arbre. Bâti au milieu de `_batir`, l'écran des commandes
	# passait sous le carton du chapitre — qui paraît au même instant à la
	# première partie — et l'on n'en voyait qu'une ligne et demie.
	_batir_les_commandes()


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
##
## Le mot est réglable : une porte dit où elle mène, faute de quoi il faudrait
## la franchir pour l'apprendre et revenir sur ses pas si ce n'était pas là.
func invite(montrer: bool, mot := "Espace") -> void:
	_invite.text = mot
	_invite.visible = montrer


## Le nom de la salle où l'on vient d'entrer, le temps de le lire.
func lieu(nom: String) -> void:
	if nom == "":
		return
	if _fondu != null and _fondu.is_valid():
		_fondu.kill()
	_lieu.text = nom
	_lieu.modulate = Color(1, 1, 1, 1)
	_fondu = create_tween()
	_fondu.tween_interval(1.6)
	_fondu.tween_property(_lieu, "modulate:a", 0.0, 0.9)


## L'écran des commandes.
##
## Bâti en dernier, donc dessiné par-dessus tout le reste — le carton du
## chapitre compris, qu'il doit couvrir puisqu'il paraît avant lui à la première
## partie.
func _batir_les_commandes() -> void:
	_commandes = Panel.new()
	_commandes.anchor_right = 1.0
	_commandes.anchor_bottom = 1.0
	_commandes.offset_left = 40
	_commandes.offset_right = -40
	_commandes.offset_top = 28
	_commandes.offset_bottom = -28

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b0a10")
	style.border_color = Color("#c08f34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(14)
	_commandes.add_theme_stylebox_override("panel", style)
	_commandes.visible = false
	add_child(_commandes)

	_commandes_texte = RichTextLabel.new()
	_commandes_texte.bbcode_enabled = true
	_commandes_texte.anchor_right = 1.0
	_commandes_texte.anchor_bottom = 1.0
	_commandes_texte.offset_left = 14
	_commandes_texte.offset_top = 10
	_commandes_texte.offset_right = -14
	_commandes_texte.offset_bottom = -10
	_commandes_texte.add_theme_font_size_override("normal_font_size", 15)
	_commandes_texte.add_theme_font_size_override("bold_font_size", 15)
	_commandes_texte.scroll_active = false
	_commandes.add_child(_commandes_texte)


func _batir_le_sac() -> void:
	# Bâti sur le gabarit du Codex, marge de contenu comprise : les enfants s'y
	# posent par rapport à la zone intérieure du panneau. Mon premier jet leur
	# donnait des décalages à la main et une ancre droite à zéro — le panneau
	# s'ouvrait tout noir, sans une erreur.
	_sac = Panel.new()
	_sac.anchor_right = 1.0
	_sac.anchor_bottom = 1.0
	var reliure := StyleBoxFlat.new()
	reliure.bg_color = Color("#0b0a10")
	reliure.border_color = Color("#c08f34")
	reliure.set_border_width_all(2)
	reliure.set_content_margin_all(20)
	_sac.add_theme_stylebox_override("panel", reliure)
	_sac.visible = false
	add_child(_sac)

	_sac_entete = _bloc(14)
	_sac_entete.anchor_right = 1.0
	_sac_entete.offset_bottom = 22
	_sac.add_child(_sac_entete)

	_sac_liste = _bloc(13)
	_sac_liste.anchor_bottom = 1.0
	_sac_liste.offset_top = 30
	_sac_liste.offset_right = COLONNE_CODEX
	_sac.add_child(_sac_liste)

	var filet := ColorRect.new()
	filet.color = Color("#2a2733")
	filet.anchor_bottom = 1.0
	filet.offset_left = COLONNE_CODEX + 8
	filet.offset_right = COLONNE_CODEX + 9
	filet.offset_top = 30
	_sac.add_child(filet)

	var marge := COLONNE_CODEX + 22

	# L'icône de la pièce choisie, à la place où le Codex met un visage : c'est
	# le même écran, et l'œil doit trouver la même chose au même endroit.
	_sac_icone = TextureRect.new()
	_sac_icone.offset_left = marge
	_sac_icone.offset_top = 32
	_sac_icone.offset_right = marge + VISAGE_CODEX
	_sac_icone.offset_bottom = 32 + VISAGE_CODEX
	_sac_icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sac_icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sac_icone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sac.add_child(_sac_icone)

	# Le texte descend plus bas que l'icône. Borné à sa hauteur, il perdait sa
	# seconde phrase — sans barre de défilement ni rien qui le signale, ce qui
	# est la pire façon de perdre du texte.
	_sac_texte = _bloc(14)
	_sac_texte.anchor_right = 1.0
	_sac_texte.offset_left = marge + VISAGE_CODEX + 12
	_sac_texte.offset_top = 30
	_sac_texte.offset_bottom = 192
	_sac.add_child(_sac_texte)

	# La vue d'équipement, à la manière d'une poupée d'habillage.
	#
	# Une liste dit ce qu'on possède ; elle ne dit pas de quoi l'on a l'air. Le
	# sprite au milieu et les emplacements autour répondent d'un coup d'œil à la
	# seule question qu'on se pose en ouvrant cet écran : qu'est-ce que je porte,
	# et qu'est-ce qui me manque ?
	_sac_doll = TextureRect.new()
	_sac_doll.offset_left = 247
	_sac_doll.offset_top = 58
	_sac_doll.offset_right = 247 + 96
	_sac_doll.offset_bottom = 58 + 96
	_sac_doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sac_doll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sac_doll.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sac_doll.visible = false
	_sac.add_child(_sac_doll)

	# Le casque au-dessus de la tête, l'arme à gauche, le bouclier à droite,
	# l'armure sous le buste, les bottes au pied de la colonne de gauche : la
	# disposition dit à quoi sert chaque case sans qu'on ait à lire son
	# étiquette. Les cases flanquent le sprite et ne le recouvrent jamais — une
	# poupée qu'on ne voit plus ne sert à rien.
	for pose in [
		{ "ou": "casque", "x": 277, "y": 18 },
		{ "ou": "arme", "x": 198, "y": 84 },
		{ "ou": "bouclier", "x": 356, "y": 84 },
		{ "ou": "armure", "x": 277, "y": 152 },
		{ "ou": "bottes", "x": 198, "y": 152 },
	]:
		var cadre := Panel.new()
		cadre.offset_left = pose["x"]
		cadre.offset_top = pose["y"]
		cadre.offset_right = int(pose["x"]) + 36
		cadre.offset_bottom = int(pose["y"]) + 36
		var boite := StyleBoxFlat.new()
		boite.bg_color = Color("#17151f")
		boite.border_color = Color("#454652")
		boite.set_border_width_all(1)
		cadre.add_theme_stylebox_override("panel", boite)
		cadre.visible = false
		_sac.add_child(cadre)

		var image := TextureRect.new()
		image.anchor_right = 1.0
		image.anchor_bottom = 1.0
		image.offset_left = 2
		image.offset_top = 2
		image.offset_right = -2
		image.offset_bottom = -2
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cadre.add_child(image)

		var etiquette := Label.new()
		etiquette.text = str(pose["ou"])
		etiquette.offset_left = int(pose["x"]) - 6
		etiquette.offset_top = int(pose["y"]) + 37
		etiquette.offset_right = int(pose["x"]) + 42
		etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		etiquette.add_theme_color_override("font_color", Color("#71727e"))
		etiquette.add_theme_font_size_override("font_size", 11)
		etiquette.visible = false
		_sac.add_child(etiquette)

		_sac_cases[str(pose["ou"])] = { "cadre": cadre, "image": image, "nom": etiquette,
			"boite": boite }

	_sac_stats = _bloc(13)
	_sac_stats.anchor_right = 1.0
	_sac_stats.anchor_bottom = 1.0
	_sac_stats.offset_left = marge
	# Dix pixels de plus : la dernière ligne du texte se coupait en deux.
	_sac_stats.offset_top = 216
	_sac.add_child(_sac_stats)


## Montre les commandes. Chaque ligne porte ses touches et ce qu'elles font.
func commandes(ouvert: bool, lignes: Array = []) -> void:
	_commandes.visible = ouvert
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	# Une ligne par commande, le pavé de touche puis ce qu'elle fait.
	#
	# Un tableau à deux colonnes alignerait les descriptions, mais Godot y serre
	# la seconde colonne au point que les lignes longues se replient sous la
	# première — et le pied de panneau se trouve poussé hors du cadre. Le bord
	# gauche irrégulier est le moindre défaut, sur sept lignes qu'on lit une
	# fois.
	var t := "[center][b][color=#f0d174]Commandes[/color][/b][/center]\n"
	for l in lignes:
		var touches := str((l as Dictionary).get("touches", ""))
		var quoi := str((l as Dictionary).get("quoi", ""))
		t += "\n[bgcolor=#23202e][color=#f0d174]  %s  [/color][/bgcolor]   %s" % [touches, quoi]
	t += "\n\n[center][color=#71727e]Espace ou Échap pour fermer[/color][/center]"
	_commandes_texte.text = t


func commandes_visible() -> bool:
	return _commandes.visible


func _batir_les_chapitres() -> void:
	_chapitres = Panel.new()
	_chapitres.anchor_right = 1.0
	_chapitres.anchor_bottom = 1.0
	var reliure := StyleBoxFlat.new()
	reliure.bg_color = Color("#0b0a10")
	reliure.border_color = Color("#c08f34")
	reliure.set_border_width_all(2)
	reliure.set_content_margin_all(20)
	_chapitres.add_theme_stylebox_override("panel", reliure)
	_chapitres.visible = false
	add_child(_chapitres)

	_chapitres_entete = _bloc(14)
	_chapitres_entete.anchor_right = 1.0
	_chapitres_entete.offset_bottom = 22
	_chapitres.add_child(_chapitres_entete)

	# La colonne est plus large que celle du Codex : un titre de chapitre est
	# une phrase, non un nom propre.
	_chapitres_liste = _bloc(13)
	_chapitres_liste.anchor_bottom = 1.0
	_chapitres_liste.offset_top = 30
	_chapitres_liste.offset_right = COLONNE_CHAPITRE
	_chapitres.add_child(_chapitres_liste)

	var filet := ColorRect.new()
	filet.color = Color("#2a2733")
	filet.anchor_bottom = 1.0
	filet.offset_left = COLONNE_CHAPITRE + 8
	filet.offset_right = COLONNE_CHAPITRE + 9
	filet.offset_top = 30
	_chapitres.add_child(filet)

	_chapitres_texte = _bloc(14)
	_chapitres_texte.anchor_right = 1.0
	_chapitres_texte.anchor_bottom = 1.0
	_chapitres_texte.offset_left = COLONNE_CHAPITRE + 22
	_chapitres_texte.offset_top = 30
	_chapitres.add_child(_chapitres_texte)


## Le contenu d'un meuble, en cases.
##
## Huit au plus, alignées : aucun coffre du jeu n'en porte davantage, et une
## grille à défilement pour deux épées serait une machine plus compliquée que ce
## qu'elle range.
const CASES_BUTIN := 8

func _batir_le_butin() -> void:
	_butin = Panel.new()
	_butin.anchor_left = 0.5
	_butin.anchor_right = 0.5
	_butin.anchor_top = 0.5
	_butin.anchor_bottom = 0.5
	_butin.offset_left = -210
	_butin.offset_right = 210
	# Deux cent quarante de haut, non deux cent huit : à deux cent huit, le
	# rappel des touches tombait hors du cadre dès qu'une description faisait
	# trois lignes — et elles en font toutes trois.
	_butin.offset_top = -120
	_butin.offset_bottom = 120
	var coffre := StyleBoxFlat.new()
	coffre.bg_color = Color("#0b0a10")
	coffre.border_color = Color("#c08f34")
	coffre.set_border_width_all(2)
	coffre.set_content_margin_all(14)
	_butin.add_theme_stylebox_override("panel", coffre)
	_butin.visible = false
	add_child(_butin)

	_butin_entete = _bloc(15)
	_butin_entete.anchor_right = 1.0
	_butin_entete.offset_bottom = 22
	_butin.add_child(_butin_entete)

	for i in CASES_BUTIN:
		var case := Panel.new()
		case.offset_left = i * 44
		case.offset_top = 30
		case.offset_right = i * 44 + 40
		case.offset_bottom = 70
		var boite := StyleBoxFlat.new()
		boite.bg_color = Color("#17151f")
		boite.border_color = Color("#454652")
		boite.set_border_width_all(1)
		case.add_theme_stylebox_override("panel", boite)
		case.visible = false
		# La souris survole et clique, puisque c'est ce qu'on attend d'un coffre.
		# Le clavier fait la même chose avec les flèches et Espace : le jeu entier
		# se joue sans souris, et cet écran n'allait pas être le seul à l'exiger.
		case.mouse_filter = Control.MOUSE_FILTER_STOP
		case.mouse_entered.connect(func() -> void: butin_survole.emit(i))
		case.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				butin_survole.emit(i)
				butin_pris.emit())
		_butin.add_child(case)

		var image := TextureRect.new()
		image.anchor_right = 1.0
		image.anchor_bottom = 1.0
		image.offset_left = 3
		image.offset_top = 3
		image.offset_right = -3
		image.offset_bottom = -3
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		case.add_child(image)
		_butin_cases.append(case)

	_butin_texte = _bloc(14)
	_butin_texte.anchor_right = 1.0
	_butin_texte.anchor_bottom = 1.0
	_butin_texte.offset_top = 80
	_butin_texte.offset_bottom = -4
	_butin.add_child(_butin_texte)


## Montre un coffre ouvert. Rien n'en sort tant qu'on n'y a pas mis la main.
func butin(ouvert: bool, etat: Dictionary = {}) -> void:
	_butin.visible = ouvert
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	var pieces: Array = etat.get("pieces", [])
	var choix := int(etat.get("choix", 0))
	_butin_entete.text = "[b][color=#f0d174]%s[/color][/b]   [color=#71727e]%d pièce%s[/color]" % [
		str(etat.get("coffre", "")), pieces.size(), "s" if pieces.size() > 1 else ""]

	for i in _butin_cases.size():
		var case := _butin_cases[i]
		case.visible = i < pieces.size()
		if i >= pieces.size():
			continue
		var p: Dictionary = pieces[i]
		(case.get_child(0) as TextureRect).texture = _icone(int(p.get("image", -1)))
		var boite: StyleBoxFlat = case.get_theme_stylebox("panel")
		boite.border_color = Color("#f0d174") if i == choix else Color("#454652")
		boite.set_border_width_all(2 if i == choix else 1)

	if pieces.is_empty():
		_butin_texte.text = ""
		return

	# L'infobulle, à la place où l'on regarde déjà : sous les cases, non
	# accrochée au curseur. Une bulle qui suit la souris n'aurait aucun sens au
	# clavier, et le jeu se joue au clavier.
	var vu: Dictionary = pieces[clampi(choix, 0, pieces.size() - 1)]
	var t := "[b][color=#f0d174]%s[/color][/b]" % str(vu.get("nom", ""))
	if str(vu.get("emplacement", "")) != "":
		t += "   [color=#71727e]%s[/color]" % str(vu.get("emplacement", ""))
	if str(vu.get("bonus", "")) != "":
		t += "\n[color=#8fd39b]%s[/color]" % str(vu.get("bonus", ""))
	for l in vu.get("texte", []):
		t += "\n%s" % str(l)
	# Court : la ligne complète dépassait la largeur du cadre et se coupait à
	# « Échap pour ». Un rappel de touches tronqué ne rappelle rien.
	t += "\n\n[color=#4a4b57]← →  choisir   ·   Espace ou clic  prendre   ·   Échap  laisser[/color]"
	_butin_texte.text = t


func butin_visible() -> bool:
	return _butin.visible


## La carte du continent.
##
## Elle occupe tout l'écran et se dessine par-dessus la salle : c'est un
## document qu'on déplie, non une vignette dans un coin. Le fond est produit à
## la production depuis `lib/carte.ts` ; les marques sont posées ici d'après les
## escales, avec la même grille de cellules — un marqueur placé à l'œil aurait
## dérivé du dessin à la première retouche.
func _batir_la_carte() -> void:
	_carte = Panel.new()
	_carte.anchor_right = 1.0
	_carte.anchor_bottom = 1.0
	var reliure := StyleBoxFlat.new()
	reliure.bg_color = Color("#22222c")
	reliure.border_color = Color("#c08f34")
	reliure.set_border_width_all(2)
	_carte.add_theme_stylebox_override("panel", reliure)
	_carte.visible = false
	add_child(_carte)

	var fond := TextureRect.new()
	fond.texture = load("res://donnees/carte.png")
	fond.anchor_right = 1.0
	fond.anchor_bottom = 1.0
	fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fond.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_carte.add_child(fond)

	# Le curseur d'abord dans l'arbre, donc sous les marques : un anneau qui
	# passerait par-dessus le point le cacherait précisément quand on le vise.
	_carte_curseur = ColorRect.new()
	_carte_curseur.color = Color("#f0d174")
	_carte_curseur.size = Vector2(14, 14)
	_carte_curseur.visible = false
	_carte.add_child(_carte_curseur)

	# Un bandeau sombre sous le texte. Sans lui, la légende se lit par-dessus le
	# désert et la mer — deux fonds clairs — et disparaît mot par mot selon
	# l'escale visée.
	var bandeau := ColorRect.new()
	bandeau.color = Color(0.043, 0.039, 0.063, 0.9)
	bandeau.anchor_top = 1.0
	bandeau.anchor_right = 1.0
	bandeau.anchor_bottom = 1.0
	bandeau.offset_top = -82
	bandeau.offset_bottom = -2
	_carte.add_child(bandeau)

	_carte_texte = _bloc(15)
	_carte_texte.anchor_top = 1.0
	_carte_texte.anchor_right = 1.0
	_carte_texte.anchor_bottom = 1.0
	_carte_texte.offset_left = 14
	_carte_texte.offset_right = -14
	# Trois lignes de quinze pixels et leurs interlignes : à cinquante-deux, la
	# troisième se dessinait par-dessus la deuxième.
	_carte_texte.offset_top = -76
	_carte_texte.offset_bottom = -6
	_carte.add_child(_carte_texte)


## Montre la carte. Les escales viennent du jeu, avec leur place en pixels.
func carte(ouvert: bool, etat: Dictionary = {}) -> void:
	_carte.visible = ouvert
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	var escales: Array = etat.get("escales", [])
	var choix := int(etat.get("choix", 0))

	# Les marques se bâtissent une fois, à la première ouverture : leur nombre
	# ne change pas d'une partie à l'autre.
	if _carte_marques.is_empty():
		for e in escales:
			var point := ColorRect.new()
			point.color = Color("#d14545")
			point.size = Vector2(6, 6)
			point.position = Vector2(e["px"], e["py"]) - Vector2(3, 3)
			_carte.add_child(point)
			_carte_marques.append(point)

			var nom := Label.new()
			nom.text = str(e["nom"])
			nom.position = Vector2(e["px"] + 8, e["py"] - 9)
			nom.add_theme_color_override("font_color", Color("#f2f2f5"))
			nom.add_theme_color_override("font_shadow_color", Color("#0b0a10"))
			nom.add_theme_constant_override("shadow_offset_x", 1)
			nom.add_theme_constant_override("shadow_offset_y", 1)
			nom.add_theme_font_size_override("font_size", 13)
			_carte.add_child(nom)

	for i in _carte_marques.size():
		var atteint := bool((escales[i] as Dictionary).get("atteint", true))
		# Le point choisi passe au blanc, non à l'or : le curseur est déjà or, et
		# deux ors superposés faisaient une tache où l'on ne distinguait plus le
		# point de son cadre.
		_carte_marques[i].color = Color("#f2f2f5") if i == choix else (
			Color("#d14545") if atteint else Color("#71727e"))

	if escales.is_empty():
		_carte_texte.text = ""
		return

	var vu: Dictionary = escales[clampi(choix, 0, escales.size() - 1)]
	_carte_curseur.visible = true
	_carte_curseur.position = Vector2(vu["px"], vu["py"]) - Vector2(7, 7)

	var t := "[b][color=#f0d174]%s[/color][/b]" % str(vu.get("nom", ""))
	if bool(vu.get("ici", false)):
		t += "   [color=#8fd39b]vous y êtes[/color]"
	if bool(vu.get("chapitre", false)):
		t += "   [color=#d14545]le chapitre vous y attend[/color]"
	t += "\n[color=#71727e]%s[/color]" % str(vu.get("quoi", ""))
	t += "\n[color=#4a4b57]← ↑ ↓ → pour choisir · Espace pour s'y rendre · Échap pour fermer[/color]"
	_carte_texte.text = t


func carte_visible() -> bool:
	return _carte.visible


## Les chapitres de la campagne, et celui qu'on regarde.
##
## Ceux qu'on n'a pas atteints restent affichés, éteints : un recueil sert
## autant à montrer ce qui manque qu'à ranger ce qu'on a.
func chapitres(ouvert: bool, etat: Dictionary = {}) -> void:
	_chapitres.visible = ouvert
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	var liste: Array = etat.get("liste", [])
	var choix := int(etat.get("choix", 0))
	var ouverts := 0
	for c in liste:
		if bool((c as Dictionary).get("joue", false)):
			ouverts += 1

	_chapitres_entete.text = "[b][color=#f0d174]Chapitres[/color][/b]   [color=#71727e]%d ouvert%s sur %d[/color]" % [
		ouverts, "s" if ouverts > 1 else "", liste.size()]

	var lignes := PackedStringArray()
	for i in liste.size():
		var c: Dictionary = liste[i]
		var titre := "%2d. %s" % [int(c.get("rang", 0)), str(c.get("titre", "?"))]
		if bool(c.get("courant", false)):
			titre += "  ●"
		var teinte := "#f0d174" if i == choix else ("#9b9caa" if bool(c.get("joue", false)) else "#4a4b57")
		lignes.append("[color=%s]%s %s[/color]" % [teinte, "▸" if i == choix else " ", titre])
	_chapitres_liste.text = "\n".join(lignes)

	if liste.is_empty():
		_chapitres_texte.text = ""
		return

	var vu: Dictionary = liste[clampi(choix, 0, liste.size() - 1)]
	var t := "[b][color=#f0d174]%s[/color][/b]\n" % str(vu.get("titre", ""))
	if str(vu.get("source", "")) != "":
		t += "[color=#71727e]%s[/color]\n" % str(vu.get("source", ""))
	if str(vu.get("avertissement", "")) != "":
		t += "\n[i][color=#9b9caa]%s[/color][/i]\n" % str(vu.get("avertissement", ""))

	if bool(vu.get("courant", false)):
		t += "\n[color=#8fd39b]C'est là que vous en êtes.[/color]"
	if bool(vu.get("joue", false)):
		t += "\n\n[color=#4a4b57]Espace pour le rejouer. Votre avance reste où elle est.[/color]"
	else:
		t += "\n\n[color=#4a4b57]Pas encore ouvert.[/color]"
	_chapitres_texte.text = t


func chapitres_visible() -> bool:
	return _chapitres.visible


## Le sac : deux catégories, ce qu'on porte, et ce que cela vaut.
##
## Les objets et les équipements ne se mélangent pas — gauche et droite passent
## de l'un à l'autre. Un équipement se porte d'une pression ; un objet se garde,
## et la ligne d'invite le dit plutôt que de laisser presser dans le vide.
func sac(ouvert: bool, etat: Dictionary = {}) -> void:
	_sac.visible = ouvert
	for element in _hud:
		element.visible = not ouvert
	if not ouvert:
		return

	var categories: Array = etat.get("categories", [])
	var courante := int(etat.get("categorie", 0))
	var liste: Array = etat.get("liste", [])
	var choix := int(etat.get("choix", 0))

	var onglets := PackedStringArray()
	for i in categories.size():
		if i == courante:
			onglets.append("[bgcolor=#23202e][color=#f0d174] %s [/color][/bgcolor]" % str(categories[i]))
		else:
			onglets.append("[color=#71727e] %s [/color]" % str(categories[i]))
	_sac_entete.text = "[b][color=#f0d174]Sac[/color][/b]   %s   [color=#4a4b57]← →[/color]" % (
		"  ".join(onglets))

	if liste.is_empty():
		_sac_liste.text = ""
		_sac_icone.texture = null
		_sac_stats.text = ""
		_sac_texte.text = "[color=#71727e][i]%s[/i][/color]" % (
			"Rien à porter encore. Les râteliers de la salle d'armes ne sont pas fermés."
			if courante == 1
			else "Rien dans le sac. Les coffres du Château ne sont pas tous fermés — approchez-vous, et regardez dedans.")
		return

	var lignes := PackedStringArray()
	for i in liste.size():
		var o: Dictionary = liste[i]
		var marque := "  ●" if bool(o.get("porte", false)) else "   "
		if i == choix:
			lignes.append("[color=#f0d174]▸ %s%s[/color]" % [str(o.get("nom", "?")), marque])
		else:
			lignes.append("[color=#9b9caa]  %s%s[/color]" % [str(o.get("nom", "?")), marque])
	_sac_liste.text = "\n".join(lignes)

	var choisi: Dictionary = liste[clampi(choix, 0, liste.size() - 1)]
	var equipement := courante == 1

	# Deux vues pour deux catégories. Un objet se regarde de près — grande
	# icône, texte à côté. Un équipement se regarde porté : le sprite au milieu
	# et les emplacements autour, comme on habille une poupée.
	_sac_icone.visible = not equipement
	_sac_doll.visible = equipement
	for ou in _sac_cases:
		(_sac_cases[ou]["cadre"] as Control).visible = equipement
		(_sac_cases[ou]["nom"] as Control).visible = equipement

	# Le texte se range à droite de la poupée, ou à droite de l'icône.
	_sac_texte.offset_left = (410 if equipement else COLONNE_CODEX + 22 + VISAGE_CODEX + 12)
	_sac_texte.offset_top = 30
	# La colonne de droite est libre sous la poupée : le texte y descend jusqu'au
	# barème, faute de quoi la seconde phrase de chaque pièce se perdait.
	_sac_texte.offset_bottom = (210 if equipement else 192)

	if equipement:
		_sac_doll.texture = _wellan_de_face(str(etat.get("sprite", "")))
		var porte: Dictionary = etat.get("porte", {})
		var vise := str(etat.get("vise", ""))
		for ou in _sac_cases:
			var case: Dictionary = _sac_cases[ou]
			var piece: Dictionary = porte.get(ou, {})
			case["image"].texture = _icone(int(piece.get("image", -1)))
			# L'emplacement que la pièce choisie occuperait s'allume : c'est ce
			# qui relie la liste de gauche à la silhouette du milieu.
			(case["boite"] as StyleBoxFlat).border_color = Color("#f0d174") if ou == vise \
				else (Color("#454652") if bool(piece.get("vide", true)) else Color("#8fd39b"))

	var rang := int(choisi.get("image", -1))
	_sac_icone.texture = _icone(rang)

	var t := "[b][color=#f0d174]%s[/color][/b]" % str(choisi.get("nom", ""))
	if bool(choisi.get("porte", false)):
		t += "   [color=#8fd39b]porté[/color]"
	t += "\n[color=#71727e]%s[/color]\n" % str(choisi.get("ou", ""))
	for l in choisi.get("texte", []):
		t += "\n%s" % str(l)
	_sac_texte.text = t

	var barème := PackedStringArray()
	for ligne in etat.get("stats", []):
		var l: Dictionary = ligne
		var a := int(l.get("valeur", 0))
		var b := int(l.get("apres", a))
		var chiffre := "[color=#dddde4]%2d[/color]" % a
		if b != a:
			# Ce que la pièce changerait, avant qu'on la porte : c'est la seule
			# information qui manque au moment où l'on hésite.
			chiffre = "[color=#dddde4]%2d[/color] [color=%s]→ %d[/color]" % [
				a, "#8fd39b" if b > a else "#d14545", b]
		barème.append("[color=#9b9caa]%-9s[/color] %s   [color=#71727e]%s[/color]" % [
			str(l.get("nom", "")), chiffre, str(l.get("effet", ""))])
	var invite := "Espace pour porter ou reposer" if bool(etat.get("equipable", false)) \
		else "Ces objets se gardent, ils ne se portent pas"
	_sac_stats.text = "\n".join(barème) + "\n\n[color=#4a4b57]%s[/color]" % invite


func sac_visible() -> bool:
	return _sac.visible


## Une icône découpée dans la planche d'inventaire.
##
## Une image par pièce serait une ressource de plus à charger pour trente-deux
## pixels ; la planche est déjà là et le moteur y taille.
func _icone(rang: int) -> Texture2D:
	if rang < 0:
		return null
	var region := AtlasTexture.new()
	region.atlas = load("res://donnees/inventaire.png")
	region.region = Rect2(rang * 32, 0, 32, 32)
	return region


## Wellan de face, première image du cycle.
##
## La rangée zéro de sa planche est la marche vers le joueur, et sa première
## colonne la pose de repos : c'est celle-là qu'on veut pour une vue
## d'équipement, non un pied en l'air.
func _wellan_de_face(planche: String) -> Texture2D:
	if planche == "":
		return null
	var atlas = load("res://assets/" + planche)
	if atlas == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = atlas
	region.region = Rect2(0, 0, 32, 32)
	return region


## Un avis passager : ce que le jeu vient d'ajouter.
func avis(texte: String) -> void:
	if texte == "":
		return
	if _fondu_avis != null and _fondu_avis.is_valid():
		_fondu_avis.kill()
	_avis.text = texte
	_avis.modulate = Color(1, 1, 1, 1)
	_fondu_avis = create_tween()
	_fondu_avis.tween_interval(2.2)
	_fondu_avis.tween_property(_avis, "modulate:a", 0.0, 0.8)


func avis_affiche() -> String:
	return _avis.text


## Ce que le bandeau de lieu affiche — pour le banc, qui ne sait pas lire l'écran.
func lieu_affiche() -> String:
	return _lieu.text


func invite_affichee() -> String:
	return _invite.text if _invite.visible else ""


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

	# Le cadre suit le nombre d'entrées : titre, ligne vide, une par option, et
	# deux de plus si un mot s'affiche. Vingt et un pixels par ligne, plus les
	# marges du style.
	var lignes_totales := 2 + options.size() + (2 if mot != "" else 0)
	var hauteur := maxf(96.0, lignes_totales * 21.0 + 28.0)
	_pause.offset_top = -hauteur / 2.0
	_pause.offset_bottom = hauteur / 2.0

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
