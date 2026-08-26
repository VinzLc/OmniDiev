extends Node2D
##
## Étape 0 — Wellan marche dans une salle du Château d'Émeraude.
##
## Tout est bâti ici plutôt que décrit dans un .tscn : la scène tient en une
## centaine de lignes lisibles, et rien ne dépend d'identifiants que l'éditeur
## aurait générés.
##
## Les deux planches viennent de l'atelier graphique et sont copiées dans
## assets/ par `npm run jeu`. Leur disposition n'est pas une convention interne
## mais celle qu'écrit `art:normalise` :
##
##   wellan.png              4 colonnes × 4 rangées de 32×32
##                           rangées : face, dos, profil gauche, profil droit
##   chateau-d-emeraude.png  16 tuiles de 16×16 en une rangée, rangées par
##                           signature de coins — colonne = NO*8+NE*4+SO*2+SE

const TUILE := 16
const SPRITE := 32
const SALLE := Vector2i(26, 15)      ## la salle, en tuiles
const VITESSE := 58.0                ## pixels par seconde
const CADENCE := 7.0                 ## images du cycle de marche par seconde

## Rangée de la planche pour chaque direction regardée.
const RANGEE := { "sud": 0, "nord": 1, "ouest": 2, "est": 3 }

var _wellan: CharacterBody2D
var _vue: Sprite2D
var _direction := "sud"
var _phase := 0.0
var _boite: CanvasLayer
var _texte: RichTextLabel
var _invite: Label
var _dans_la_zone := false
var _ouverte := false


func _ready() -> void:
	# Vue de dessus : ce qui est plus bas à l'écran est plus près, donc devant.
	# Sans cela, Wellan passe derrière un objet qu'il devrait masquer.
	y_sort_enabled = true

	_batir_le_sol()
	_batir_les_murs()
	_batir_wellan()
	_batir_le_dialogue()
	_batir_le_brasero()

	# Mode de contrôle : on rend quelques images, on en garde une, on sort. Sert
	# à regarder la scène sans avoir à la jouer — la seule façon de vérifier
	# qu'elle est juste, puisqu'aucune mesure ne dit qu'un décor est lisible.
	if OS.get_cmdline_args().has("--capture"):
		_capturer()


## Joue une courte partie et en garde des images.
##
## On passe par `Input.action_press` plutôt que par les variables internes : le
## code traversé est exactement celui d'un joueur, touches comprises. Une
## vérification qui contourne le chemin normal ne prouve rien de ce chemin.
func _capturer() -> void:
	await _garder("00-depart", 12)

	# Monter l'allée : la direction doit passer au dos, le cycle doit défiler,
	# et la position doit vraiment changer.
	var depart := _wellan.global_position
	Input.action_press("ui_up")
	await _garder("01-marche-nord", 40)
	Input.action_release("ui_up")
	var parcouru := depart.distance_to(_wellan.global_position)
	print("PARCOURU %.1f px, direction %s" % [parcouru, _direction])

	# Buter contre le mur. On le pose à deux pas plutôt que de le faire traverser
	# la salle : en mode capture, l'enregistrement des images ralentit la boucle
	# et la physique prend du retard, si bien qu'une longue marche mesure la
	# lenteur du test et non le comportement du jeu.
	_wellan.global_position = Vector2(13.0 * TUILE, 3.0 * TUILE)
	Input.action_press("ui_up")
	await _garder("02-contre-le-mur", 90)
	Input.action_release("ui_up")
	print("ARRET y=%.1f (le mur occupe y<0)" % _wellan.global_position.y)

	# Redescendre jusqu'au brasier, puis parler. On le repose au-dessus de lui et
	# on le laisse s'en approcher par ses propres jambes : c'est l'entrée dans la
	# zone qu'on éprouve, pas l'endurance du test.
	_wellan.global_position = Vector2(13.0 * TUILE, 3.5 * TUILE)
	Input.action_press("ui_down")
	await _garder("03-marche-sud", 90)
	Input.action_release("ui_down")
	print("ZONE %s à y=%.1f" % [_dans_la_zone, _wellan.global_position.y])

	if _dans_la_zone:
		# `Input.action_press` ne fait que positionner l'état de l'action : aucun
		# événement ne remonte, et `_unhandled_input` n'en voit rien. Pour
		# éprouver le chemin d'un vrai joueur il faut injecter l'événement.
		var touche := InputEventAction.new()
		touche.action = "ui_accept"
		touche.pressed = true
		Input.parse_input_event(touche)
		await _garder("04-dialogue", 20)
		print("DIALOGUE %s" % _ouverte)

	get_tree().quit()


func _garder(nom: String, images: int) -> void:
	for i in images:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)


## Le sol, en tuiles de Wang.
##
## Chaque tuile se choisit par ses quatre coins : on demande à chaque sommet de
## la grille s'il est tapis ou dalle, et les quatre réponses forment le numéro
## de la colonne. C'est ce qui permet au tapis d'avoir n'importe quelle forme
## sans qu'on dessine un seul cas particulier.
func _batir_le_sol() -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/chateau-d-emeraude.png")
	atlas.texture_region_size = Vector2i(TUILE, TUILE)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))

	var jeu := TileSet.new()
	jeu.tile_size = Vector2i(TUILE, TUILE)
	jeu.add_source(atlas, 0)

	var carte := TileMapLayer.new()
	carte.tile_set = jeu
	add_child(carte)

	for y in SALLE.y:
		for x in SALLE.x:
			var signature := 0
			for coin in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
				signature = (signature << 1) | (0 if _est_tapis(coin) else 1)
			carte.set_cell(Vector2i(x, y), 0, Vector2i(signature, 0))


## Le tapis : une allée centrale, élargie en son milieu.
##
## Sa forme n'est pas décorative. Une caméra qui tient quinze tuiles de large
## doit montrer une frontière presque tout le temps, sans quoi le joueur ne voit
## qu'un aplat — et le raccord, qui a coûté cinq générations, ne se voit jamais.
func _est_tapis(sommet: Vector2i) -> bool:
	var allee := sommet.x >= 11 and sommet.x <= 15 and sommet.y >= 2 and sommet.y <= SALLE.y - 2
	var estrade := sommet.x >= 8 and sommet.x <= 18 and sommet.y >= 3 and sommet.y <= 8
	return allee or estrade


## Les murs.
##
## Faute de tuiles murales, la salle est bordée d'une bande sombre et de
## collisions. Ce n'est pas un pis-aller visuel : une grande salle voûtée dont
## on ne voit pas les bords se lit très bien ainsi, et le jour où les tuiles
## arriveront, seul l'habillage changera.
func _batir_les_murs() -> void:
	var sol := Rect2(Vector2.ZERO, Vector2(SALLE) * TUILE)
	var mur := 8.0

	var cadre := ColorRect.new()
	cadre.color = Color("#0b0a10")
	cadre.position = sol.position - Vector2(mur * 8, mur * 8)
	cadre.size = sol.size + Vector2(mur * 16, mur * 16)
	cadre.z_index = -10
	add_child(cadre)

	var corps := StaticBody2D.new()
	add_child(corps)
	var bords := [
		Rect2(sol.position.x, sol.position.y - mur, sol.size.x, mur),                  # haut
		Rect2(sol.position.x, sol.end.y, sol.size.x, mur),                             # bas
		Rect2(sol.position.x - mur, sol.position.y - mur, mur, sol.size.y + mur * 2),  # gauche
		Rect2(sol.end.x, sol.position.y - mur, mur, sol.size.y + mur * 2),             # droite
	]
	for bord in bords:
		var forme := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = bord.size
		forme.shape = rect
		forme.position = bord.position + bord.size / 2.0
		corps.add_child(forme)


func _batir_wellan() -> void:
	_wellan = CharacterBody2D.new()
	# Au bas de l'allée, face à l'estrade : il y a quelque part où aller.
	_wellan.position = Vector2(13.0 * TUILE, (SALLE.y - 2) * TUILE)
	add_child(_wellan)

	_vue = Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load("res://assets/wellan.png")
	region.region = Rect2(0, 0, SPRITE, SPRITE)
	_vue.texture = region
	# Le sprite est calé sur ses pieds : c'est ce point qui touche le sol, et
	# c'est lui qui doit coïncider avec la position du corps.
	_vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	_wellan.add_child(_vue)

	# La collision ne prend que le bas du personnage. Un rectangle à sa taille
	# entière l'empêcherait de s'approcher des murs, alors que dans une vue de
	# dessus seuls ses pieds occupent le sol.
	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	_wellan.add_child(forme)

	var camera := Camera2D.new()
	# Le double : la vue tient une quinzaine de tuiles en largeur, comme les jeux
	# dont on s'inspire. Sans cela, la salle entière entre dans l'écran et le
	# personnage n'est plus qu'un point.
	camera.zoom = Vector2(2, 2)
	camera.limit_left = -8
	camera.limit_top = -8
	camera.limit_right = SALLE.x * TUILE + 8
	camera.limit_bottom = SALLE.y * TUILE + 8
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	_wellan.add_child(camera)


func _batir_le_brasero() -> void:
	# Rien à afficher encore — le lieu se signale par une invite. Il tiendra sa
	# tuile quand l'atelier en produira une.
	var zone := Area2D.new()
	zone.position = Vector2(13.0 * TUILE, 5.0 * TUILE)
	add_child(zone)

	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = 22
	forme.shape = cercle
	zone.add_child(forme)

	# Un jalon, pas un décor : il tiendra sa tuile quand l'atelier en produira
	# une. Cerclé de noir pour qu'il se lise comme un objet et non comme un
	# défaut du sol.
	var socle := ColorRect.new()
	socle.color = Color("#0b0a10")
	socle.size = Vector2(12, 12)
	socle.position = Vector2(-6, -6)
	zone.add_child(socle)

	var flamme := ColorRect.new()
	flamme.color = Color("#f0d174")
	flamme.size = Vector2(6, 6)
	flamme.position = Vector2(-3, -3)
	zone.add_child(flamme)

	zone.body_entered.connect(func(corps): if corps == _wellan: _dans_la_zone = true; _invite.visible = true)
	zone.body_exited.connect(func(corps): if corps == _wellan: _dans_la_zone = false; _invite.visible = false)


func _batir_le_dialogue() -> void:
	_boite = CanvasLayer.new()
	add_child(_boite)

	var fond := Panel.new()
	fond.anchor_left = 0.0
	fond.anchor_right = 1.0
	fond.anchor_top = 1.0
	fond.anchor_bottom = 1.0
	fond.offset_left = 12
	fond.offset_right = -12
	fond.offset_top = -92
	fond.offset_bottom = -12

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b0a10")
	style.border_color = Color("#c08f34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(10)
	fond.add_theme_stylebox_override("panel", style)
	fond.visible = false
	_boite.add_child(fond)

	_texte = RichTextLabel.new()
	_texte.bbcode_enabled = true
	_texte.anchor_right = 1.0
	_texte.anchor_bottom = 1.0
	_texte.offset_left = 10
	_texte.offset_top = 8
	_texte.offset_right = -10
	_texte.offset_bottom = -8
	# Douze pixels dans une fenêtre qui en fait 270 de haut. À quinze, la
	# réplique débordait du cadre et Godot ajoutait une barre de défilement —
	# une boîte de dialogue qu'il faut faire défiler n'en est pas une.
	_texte.add_theme_font_size_override("normal_font_size", 12)
	_texte.add_theme_font_size_override("bold_font_size", 12)
	_texte.scroll_active = false
	fond.add_child(_texte)

	_invite = Label.new()
	_invite.text = "Espace"
	_invite.anchor_left = 0.5
	_invite.anchor_right = 0.5
	_invite.anchor_top = 1.0
	_invite.anchor_bottom = 1.0
	_invite.offset_left = -40
	_invite.offset_right = 40
	_invite.offset_top = -110
	_invite.offset_bottom = -92
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite.add_theme_color_override("font_color", Color("#f0d174"))
	_invite.visible = false
	_boite.add_child(_invite)

	_boite.set_meta("fond", fond)


func _unhandled_input(evenement: InputEvent) -> void:
	if not evenement.is_action_pressed("ui_accept"):
		return
	var fond: Panel = _boite.get_meta("fond")
	if _ouverte:
		_ouverte = false
		fond.visible = false
		_invite.visible = _dans_la_zone
	elif _dans_la_zone:
		_ouverte = true
		fond.visible = true
		_invite.visible = false
		_texte.text = "[b]Wellan[/b]\nLe feu du Château ne s'éteint jamais. Tant qu'il brûle, l'Ordre tient."


func _physics_process(delta: float) -> void:
	if _ouverte:
		_wellan.velocity = Vector2.ZERO
		_dessiner(0)
		return

	var pas := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_wellan.velocity = pas * VITESSE
	_wellan.move_and_slide()

	if pas == Vector2.ZERO:
		_phase = 0.0
		_dessiner(0)
		return

	# La direction regardée suit l'axe dominant : en diagonale, on continue de
	# faire face au côté vers lequel on avance le plus franchement.
	if absf(pas.x) > absf(pas.y):
		_direction = "est" if pas.x > 0.0 else "ouest"
	else:
		_direction = "sud" if pas.y > 0.0 else "nord"

	_phase = fmod(_phase + delta * CADENCE, 4.0)
	_dessiner(int(_phase))


func _dessiner(colonne: int) -> void:
	var region: AtlasTexture = _vue.texture
	region.region = Rect2(colonne * SPRITE, RANGEE[_direction] * SPRITE, SPRITE, SPRITE)
