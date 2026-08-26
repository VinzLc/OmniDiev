extends Node2D
##
## La salle se lit, elle ne s'écrit plus.
##
## Rien ici ne connaît Wellan, le Château ni le Roi. La scène ouvre deux
## fichiers — le monde produit depuis le Codex, et la salle écrite à la main —
## et bâtit ce qu'ils décrivent. Ajouter un personnage tient en trois nombres et
## l'identifiant de sa fiche ; son nom, son rôle et ses liens en viennent tout
## seuls.
##
## C'est ce qui rend l'échelle tenable : 365 personnages et 57 lieux attendent
## dans monde.json, et aucun ne demandera qu'on retouche ce fichier.

const TUILE := 16
const SPRITE := 32
const VITESSE := 58.0
const CADENCE := 7.0

## Rangée de la planche pour chaque direction regardée.
const RANGEE := { "sud": 0, "nord": 1, "ouest": 2, "est": 3 }

const DONNEES := "res://donnees/"
const SCENE_INITIALE := "i-01"

var _monde: Dictionary
var _salle: Dictionary
var _scene: Dictionary

## Où en est le chapitre, et à qui l'on a déjà parlé dans l'étape en cours.
var _etape := 0
var _parles := {}
var _habitants := {}
var _objectif: Label

var _wellan: CharacterBody2D
var _vue: Sprite2D
var _direction := "sud"
var _phase := 0.0

var _a_portee := {}            ## tous ceux dont on est assez près
var _proche := ""              ## celui qu'on aborderait, le plus proche d'entre eux
var _interlocuteur := ""       ## à qui l'on parle en ce moment
var _pages: PackedStringArray = []
var _page := 0
var _ouverte := false

var _cadre: Panel
var _texte: RichTextLabel
var _invite: Label


func _ready() -> void:
	# Vue de dessus : ce qui est plus bas à l'écran est plus près, donc devant.
	y_sort_enabled = true

	_monde = _lire(DONNEES + "monde.json")
	_scene = _lire(DONNEES + "scenes/%s.json" % SCENE_INITIALE)
	_salle = _lire(DONNEES + "salles/%s.json" % _scene.get("salle", ""))
	if _monde.is_empty() or _salle.is_empty() or _scene.is_empty():
		push_error("Données absentes. Lancer : npm run jeu:donnees")
		return

	_batir_le_sol()
	_batir_les_murs()
	_batir_wellan()
	_batir_le_dialogue()
	_peupler()
	_entrer_dans_l_etape()

	if OS.get_cmdline_args().has("--capture"):
		_capturer()


func _lire(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		return {}
	var contenu = JSON.parse_string(FileAccess.get_file_as_string(chemin))
	return contenu if contenu is Dictionary else {}


func _taille() -> Vector2i:
	var t: Array = _salle.get("taille", [26, 15])
	return Vector2i(int(t[0]), int(t[1]))


## Le sol, en tuiles de Wang.
##
## Chaque tuile se choisit par ses quatre coins : on demande à chaque sommet de
## la grille s'il est tapis ou dalle, et les quatre réponses forment le numéro de
## la colonne. C'est ce qui permet au tapis d'avoir n'importe quelle forme sans
## qu'on dessine un seul cas particulier.
func _batir_le_sol() -> void:
	var lieu: Dictionary = _monde["lieux"].get(_salle.get("lieu", ""), {})
	var tuiles = lieu.get("tuiles")
	if tuiles == null:
		push_error("Le lieu « %s » n'a pas de tuiles." % _salle.get("lieu", ""))
		return

	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/" + str(tuiles))
	atlas.texture_region_size = Vector2i(TUILE, TUILE)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))

	var jeu := TileSet.new()
	jeu.tile_size = Vector2i(TUILE, TUILE)
	jeu.add_source(atlas, 0)

	var carte := TileMapLayer.new()
	carte.tile_set = jeu
	add_child(carte)

	var taille := _taille()
	for y in taille.y:
		for x in taille.x:
			var signature := 0
			for coin in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
				signature = (signature << 1) | (0 if _est_tapis(coin) else 1)
			carte.set_cell(Vector2i(x, y), 0, Vector2i(signature, 0))


func _est_tapis(sommet: Vector2i) -> bool:
	for zone in _salle.get("tapis", []):
		if sommet.x >= int(zone["x"]) and sommet.x <= int(zone["x"]) + int(zone["l"]) \
			and sommet.y >= int(zone["y"]) and sommet.y <= int(zone["y"]) + int(zone["h"]):
			return true
	return false


## Les murs.
##
## Faute de tuiles murales, la salle est bordée d'une bande sombre et de
## collisions. Le jour où les tuiles arriveront, seul l'habillage changera.
func _batir_les_murs() -> void:
	var sol := Rect2(Vector2.ZERO, Vector2(_taille()) * TUILE)
	var mur := 8.0

	var cadre := ColorRect.new()
	cadre.color = Color("#0b0a10")
	cadre.position = sol.position - Vector2(mur * 8, mur * 8)
	cadre.size = sol.size + Vector2(mur * 16, mur * 16)
	cadre.z_index = -10
	add_child(cadre)

	var corps := StaticBody2D.new()
	add_child(corps)
	for bord in [
		Rect2(sol.position.x, sol.position.y - mur, sol.size.x, mur),
		Rect2(sol.position.x, sol.end.y, sol.size.x, mur),
		Rect2(sol.position.x - mur, sol.position.y - mur, mur, sol.size.y + mur * 2),
		Rect2(sol.end.x, sol.position.y - mur, mur, sol.size.y + mur * 2),
	]:
		var forme := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = bord.size
		forme.shape = rect
		forme.position = bord.position + bord.size / 2.0
		corps.add_child(forme)


## La vue d'un personnage : sa planche s'il en a une, la silhouette sinon.
##
## Un personnage sans art n'est pas absent du jeu — il y paraît teinté d'après
## son identifiant, et on lui parle. Attendre que l'art soit prêt pour écrire le
## contenu reviendrait à ne jamais avancer.
func _sprite_de(fiche: Dictionary) -> Sprite2D:
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	var planche = fiche.get("planche")
	if planche != null:
		region.atlas = load("res://assets/" + str(planche))
	else:
		region.atlas = load(DONNEES + "silhouette.png")
		vue.modulate = Color(fiche.get("teinte", "#736c82"))
	region.region = Rect2(0, 0, SPRITE, SPRITE)
	vue.texture = region
	# Le sprite est calé sur ses pieds : c'est ce point qui touche le sol.
	vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	return vue


func _batir_wellan() -> void:
	var depart: Array = _salle.get("depart", [1, 1])
	_wellan = CharacterBody2D.new()
	_wellan.position = Vector2(float(depart[0]) * TUILE, float(depart[1]) * TUILE)
	add_child(_wellan)

	_vue = _sprite_de(_monde["personnages"].get("wellan", {}))
	_wellan.add_child(_vue)

	# La collision ne prend que le bas du personnage : dans une vue de dessus,
	# seuls ses pieds occupent le sol.
	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	_wellan.add_child(forme)

	var taille := _taille()
	var camera := Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.limit_left = -8
	camera.limit_top = -8
	camera.limit_right = taille.x * TUILE + 8
	camera.limit_bottom = taille.y * TUILE + 8
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	_wellan.add_child(camera)


func _peupler() -> void:
	for habitant in _salle.get("personnages", []):
		_faire_entrer(habitant)
	for objet in _salle.get("objets", []):
		_batir_objet(str(objet.get("type", "")), Vector2(float(objet["x"]) * TUILE, float(objet["y"]) * TUILE))


func _faire_entrer(habitant: Dictionary) -> void:
	var id := str(habitant["fiche"])
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	if fiche.is_empty():
		push_warning("Fiche inconnue : %s" % id)
		return
	if _habitants.has(id):
		return

	var corps := StaticBody2D.new()
	corps.position = Vector2(float(habitant["x"]) * TUILE, float(habitant["y"]) * TUILE)
	add_child(corps)

	var vue := _sprite_de(fiche)
	var region: AtlasTexture = vue.texture
	region.region = Rect2(0, RANGEE.get(habitant.get("regarde", "sud"), 0) * SPRITE, SPRITE, SPRITE)
	corps.add_child(vue)

	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	corps.add_child(forme)

	_zone_de_parole(corps, id)
	_habitants[id] = corps


func _faire_sortir(id: String) -> void:
	if not _habitants.has(id):
		return
	_a_portee.erase(id)
	if _proche == id:
		_proche = ""
		_invite.visible = false
	_habitants[id].queue_free()
	_habitants.erase(id)


## ── Le chapitre ───────────────────────────────────────────────────────────
##
## Une étape attend qu'on ait parlé à quelqu'un, ou à tout un groupe. Quand
## c'est fait, les entrées et sorties qu'elle décrit s'appliquent et l'objectif
## change. Rien de tout cela n'est écrit ici : la scène est un fichier.

func _etape_courante() -> Dictionary:
	var etapes: Array = _scene.get("etapes", [])
	if _etape < etapes.size():
		return etapes[_etape]
	return _scene.get("fin", {})


func _entrer_dans_l_etape() -> void:
	var etape := _etape_courante()
	_parles.clear()

	for sortant in etape.get("disparaissent", []):
		_faire_sortir(str(sortant))
	for entrant in etape.get("apparaissent", []):
		_faire_entrer(entrant)

	_objectif.text = str(etape.get("objectif", ""))


## L'étape est-elle satisfaite par ce qu'on vient d'entendre ?
func _avancer_si_possible() -> void:
	var attend: Dictionary = _etape_courante().get("attend", {})
	if attend.is_empty():
		return

	if attend.has("parler") and _parles.has(str(attend["parler"])):
		_etape += 1
		_entrer_dans_l_etape()
		return

	if attend.has("parler_tous"):
		var reste := 0
		for id in attend["parler_tous"]:
			if not _parles.has(str(id)):
				reste += 1
		if reste == 0:
			_etape += 1
			_entrer_dans_l_etape()
		else:
			# Un objectif qui décompte vaut mieux qu'un objectif qui répète :
			# le joueur voit ce qui lui reste sans tenir le compte lui-même.
			_objectif.text = "%s (%d)" % [_etape_courante().get("objectif", ""), reste]


## De quoi savoir qu'on peut parler, et à qui.
##
## On retient tous ceux qui sont à portée, et l'on tranche par la distance à
## chaque image plutôt qu'à l'entrée dans la zone.
##
## Le premier jet nommait simplement le dernier entré. Dans une salle où six
## Chevaliers se tiennent à deux tuiles les uns des autres, leurs cercles se
## recoupent, et Wellan abordait quelqu'un qu'il n'avait pas visé — sans qu'on
## puisse rien y faire, puisque se rapprocher ne changeait rien.
func _zone_de_parole(parent: Node2D, id: String) -> void:
	var zone := Area2D.new()
	parent.add_child(zone)

	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = 22
	forme.shape = cercle
	zone.add_child(forme)

	zone.body_entered.connect(func(corps: Node) -> void:
		if corps == _wellan:
			_a_portee[id] = parent)
	zone.body_exited.connect(func(corps: Node) -> void:
		if corps == _wellan:
			_a_portee.erase(id))


func _choisir_l_interlocuteur() -> void:
	var meilleur := ""
	var plus_court := INF
	for id in _a_portee:
		var qui: Node2D = _a_portee[id]
		if not is_instance_valid(qui):
			continue
		var d := _wellan.global_position.distance_to(qui.global_position)
		if d < plus_court:
			plus_court = d
			meilleur = str(id)
	_proche = meilleur
	if not _ouverte:
		_invite.visible = _proche != ""


func _batir_objet(genre: String, ou: Vector2) -> void:
	# Un jalon, pas un décor : il tiendra sa tuile quand l'atelier en produira
	# une. Cerclé de noir pour se lire comme un objet et non comme un défaut du
	# sol.
	#
	# En Sprite2D et non en ColorRect : un Control ne participe pas au tri par
	# profondeur et se dessine dans l'ordre de l'arbre. Le brasier passait ainsi
	# devant Wellan et lui posait un carré noir sur la tête.
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color("#0b0a10"))
	var coeur := Color("#f0d174") if genre == "brasier" else Color("#736c82")
	for y in range(3, 9):
		for x in range(3, 9):
			image.set_pixel(x, y, coeur)

	var vue := Sprite2D.new()
	vue.texture = ImageTexture.create_from_image(image)
	vue.position = ou
	add_child(vue)


func _batir_le_dialogue() -> void:
	var couche := CanvasLayer.new()
	add_child(couche)

	_cadre = Panel.new()
	_cadre.anchor_right = 1.0
	_cadre.anchor_top = 1.0
	_cadre.anchor_bottom = 1.0
	_cadre.offset_left = 12
	_cadre.offset_right = -12
	_cadre.offset_top = -92
	_cadre.offset_bottom = -12

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b0a10")
	style.border_color = Color("#c08f34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(10)
	_cadre.add_theme_stylebox_override("panel", style)
	_cadre.visible = false
	couche.add_child(_cadre)

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
	_texte.add_theme_font_size_override("normal_font_size", 12)
	_texte.add_theme_font_size_override("bold_font_size", 12)
	_texte.scroll_active = false
	_cadre.add_child(_texte)

	_invite = Label.new()
	_invite.text = "Espace"
	_invite.anchor_left = 0.5
	_invite.anchor_right = 0.5
	_invite.anchor_top = 1.0
	_invite.anchor_bottom = 1.0
	_invite.offset_left = -40
	_invite.offset_right = 40
	_invite.offset_top = -112
	_invite.offset_bottom = -94
	_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite.add_theme_color_override("font_color", Color("#f0d174"))
	_invite.visible = false
	couche.add_child(_invite)

	# L'objectif reste affiché : sans lui, un chapitre en quatre temps se joue à
	# tâtons, et le joueur croit que le jeu ne réagit pas alors qu'il attend.
	_objectif = Label.new()
	_objectif.anchor_right = 1.0
	_objectif.offset_left = 14
	_objectif.offset_top = 8
	_objectif.offset_right = -14
	_objectif.add_theme_color_override("font_color", Color("#f0d174"))
	_objectif.add_theme_color_override("font_shadow_color", Color("#0b0a10"))
	_objectif.add_theme_constant_override("shadow_offset_x", 1)
	_objectif.add_theme_constant_override("shadow_offset_y", 1)
	_objectif.add_theme_font_size_override("font_size", 12)
	couche.add_child(_objectif)


## Ce que dit un personnage.
##
## La scène en cours d'abord : si le chapitre lui a écrit des répliques pour
## cette étape, ce sont celles-là. Sa fiche à défaut — de sorte qu'aucun
## personnage ne soit jamais muet, même ajouté à la dernière minute et sans une
## ligne écrite pour lui.
func _repliques(id: String) -> PackedStringArray:
	var ecrites: Dictionary = _etape_courante().get("dialogues", {})
	if ecrites.has(id):
		var pages := PackedStringArray()
		for ligne in ecrites[id]:
			var qui := str(ligne.get("qui", ""))
			var dit := str(ligne.get("dit", ""))
			if qui == "recit":
				# Le récit n'a pas de nom : c'est ce que le joueur voit, non ce
				# qu'on lui dit.
				pages.append("[i]%s[/i]" % dit)
			else:
				var nom := str(_monde["personnages"].get(qui, {}).get("nom", qui))
				pages.append("[b]%s[/b]\n%s" % [nom, dit])
		return pages
	return _fiche_en_repliques(id)


## Le pis-aller : ce que la fiche du Codex permet de dire.
func _fiche_en_repliques(id: String) -> PackedStringArray:
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	var nom := str(fiche.get("nom", id))
	var pages := PackedStringArray()
	pages.append("[b]%s[/b]\n%s" % [nom, fiche.get("role", "")])

	var liens: Array = fiche.get("liens", [])
	if not liens.is_empty():
		var dits := PackedStringArray()
		for lien in liens.slice(0, 2):
			# Le Codex empile les nuances d'un lien en les séparant par des
			# points-virgules. Tout dire ferait de la réplique une fiche ; on
			# garde la première nuance, qui est la plus générale.
			var nature := str(lien["nature"]).split(";")[0].strip_edges()
			dits.append("%s — %s" % [lien["nom"], nature])
		pages.append("[b]%s[/b]\n%s" % [nom, "\n".join(dits)])

	var tomes: Array = fiche.get("tomes", [])
	if tomes.size() > 1:
		pages.append("[b]%s[/b]\nParaît dans %d des 44 volumes, du tome %d au tome %d."
			% [nom, tomes.size(), int(tomes[0]), int(tomes[-1])])
	return pages


func _afficher() -> void:
	if _page >= _pages.size():
		_ouverte = false
		_cadre.visible = false
		_invite.visible = _proche != ""
		# On ne compte l'échange que s'il a été mené jusqu'au bout : entamer une
		# conversation et s'en aller ne fait pas avancer le chapitre.
		if _interlocuteur != "":
			_parles[_interlocuteur] = true
			_interlocuteur = ""
			_avancer_si_possible()
		return
	_texte.text = _pages[_page]


func _unhandled_input(evenement: InputEvent) -> void:
	if not evenement.is_action_pressed("ui_accept"):
		return
	if _ouverte:
		_page += 1
		_afficher()
	elif _proche != "":
		_interlocuteur = _proche
		_pages = _repliques(_proche)
		_page = 0
		_ouverte = true
		_cadre.visible = true
		_invite.visible = false
		_afficher()


func _physics_process(delta: float) -> void:
	_choisir_l_interlocuteur()

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


## Joue le chapitre en entier et en garde des images.
##
## On passe par `Input.parse_input_event` : le code traversé est celui d'un
## joueur, touches comprises. Une vérification qui contourne le chemin normal ne
## prouve rien de ce chemin.
##
## Wellan est reposé près de chacun plutôt que promené à travers la salle :
## l'enregistrement des images ralentit la boucle et la physique prend du
## retard, si bien qu'une longue marche mesure la lenteur du test et non le
## comportement du jeu. La marche, elle, est éprouvée une fois, au début.
func _capturer() -> void:
	await _garder("00-salle", 12)
	print("OBJECTIF %s" % _objectif.text)

	var depart := _wellan.global_position
	Input.action_press("ui_up")
	await _garder("01-marche", 40)
	Input.action_release("ui_up")
	print("PARCOURU %.1f px, direction %s" % [depart.distance_to(_wellan.global_position), _direction])

	await _parler_a("emeraude-ier", "02-le-roi")
	print("OBJECTIF %s" % _objectif.text)

	for compagnon in ["santo", "bergeau", "jasson", "dempsey", "falcon", "chloe"]:
		await _parler_a(compagnon, "03-%s" % compagnon)
		print("OBJECTIF %s" % _objectif.text)

	await _parler_a("armene", "04-armene")
	print("OBJECTIF %s" % _objectif.text)

	await _parler_a("fan", "05-la-reine")
	print("OBJECTIF %s" % _objectif.text)
	print("ETAPE %d sur %d" % [_etape, _scene.get("etapes", []).size()])

	get_tree().quit()


## Aborde un personnage et l'écoute jusqu'au bout.
func _parler_a(id: String, nom_image: String) -> void:
	if not _habitants.has(id):
		print("ABSENT %s" % id)
		return
	_wellan.global_position = _habitants[id].position + Vector2(0, TUILE)
	for i in 6:
		await get_tree().process_frame
	if _proche != id:
		print("HORS DE PORTEE %s (proche=%s)" % [id, _proche])
		return

	var pages := 0
	while pages < 12:
		var touche := InputEventAction.new()
		touche.action = "ui_accept"
		touche.pressed = true
		Input.parse_input_event(touche)
		await get_tree().process_frame
		await get_tree().process_frame
		pages += 1
		# L'image se prend au milieu de l'échange, cadre ouvert. La prendre à la
		# fin ne montrait que la salle vide : on vérifiait que le dialogue se
		# ferme, non qu'il s'affiche.
		if pages == 2 and _ouverte:
			get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom_image)
		if not _ouverte and pages > 1:
			break
	print("PARLE %s en %d pages" % [id, pages])


func _garder(nom: String, images: int) -> void:
	for i in images:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)
