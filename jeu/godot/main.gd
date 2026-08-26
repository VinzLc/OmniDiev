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
const PROGRESSION := "user://progression.json"

## Le combat, en clair. Ces nombres sont à nous ; ce qui vient du texte, c'est
## que la carapace des hommes-insectes boit la magie.
const VIE_WELLAN := 8
const ENERGIE_MAX := 100.0
const COUT_DU_SORT := 25.0
const REGAIN := 14.0          ## énergie par seconde
const REPOS_EPEE := 0.38      ## secondes entre deux coups
const PORTEE_EPEE := 22.0
const DEGATS_EPEE := 1
const DEGATS_SORT := 3
const VITESSE_SORT := 170.0
const PORTEE_SORT := 220.0

var _monde: Dictionary
var _salle: Dictionary
var _scene: Dictionary
var _campagne: Dictionary
var _chapitre := ""
var _libre := false          ## scène imposée en ligne de commande : on ne note rien
var _acheve: Panel

## Où en est le chapitre, et à qui l'on a déjà parlé dans l'étape en cours.
var _etape := 0
var _parles := {}
var _habitants := {}
var _objectif: Label

var _energie := ENERGIE_MAX
var _prochain_coup := 0.0
var _ennemis: Array = []
var _traits: Array = []       ## les sorts en vol
var _vaincu := false
var _jauge_vie: ColorRect
var _jauge_energie: ColorRect
var _defaite: Panel

var _wellan: Combattant
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
	_campagne = _lire(DONNEES + "campagne.json")
	_chapitre = _scene_demandee()
	_noter(_chapitre)
	_scene = _lire(DONNEES + "scenes/%s.json" % _chapitre)
	_salle = _lire(DONNEES + "salles/%s.json" % _scene.get("salle", ""))
	if _monde.is_empty() or _salle.is_empty() or _scene.is_empty():
		push_error("Données absentes. Lancer : npm run jeu:donnees")
		return

	_declarer_les_touches()
	_batir_le_sol()
	_batir_les_murs()
	_batir_wellan()
	_batir_le_dialogue()
	_peupler()
	_tomber_la_nuit()
	_entrer_dans_l_etape()

	# Le drapeau peut arriver des deux côtés de `++` selon la façon dont on
	# lance : on regarde les deux listes plutôt que d'imposer un ordre.
	if OS.get_cmdline_args().has("--capture") or OS.get_cmdline_user_args().has("--capture"):
		_capturer()
	elif OS.get_cmdline_user_args().has("--effets"):
		_capturer_les_effets()


## Les touches d'action.
##
## Déclarées ici plutôt que dans project.godot : la sérialisation des
## événements d'entrée dans ce fichier est illisible et se corrompt à la
## moindre retouche à la main. Trois lignes de code valent mieux.
func _declarer_les_touches() -> void:
	for nom in [["frapper", KEY_J], ["lancer", KEY_K]]:
		if InputMap.has_action(nom[0]):
			continue
		InputMap.add_action(nom[0])
		var touche := InputEventKey.new()
		touche.physical_keycode = nom[1]
		InputMap.action_add_event(nom[0], touche)


## Quel chapitre jouer ?
##
## Celui qu'on impose en ligne de commande — `++ --scene i-01` — et sinon celui
## où l'on en était. La partie se poursuit d'elle-même : c'est ce qui fait d'une
## suite de scènes une histoire.
##
## Les arguments passent après `++`, non avant : tout ce qui précède appartient
## au moteur, et un mot sans tiret y est pris pour un chemin de scène à charger.
func _scene_demandee() -> String:
	var arguments := OS.get_cmdline_user_args()
	var i := arguments.find("--scene")
	if i >= 0 and i + 1 < arguments.size():
		_libre = true
		return arguments[i + 1]

	var suite: Array = _campagne.get("chapitres", [])
	var repris: String = str(_lire(PROGRESSION).get("chapitre", ""))
	if repris != "" and suite.has(repris):
		return str(repris)
	return str(suite[0]) if not suite.is_empty() else "i-01"


## Note où l'on en est. Une scène imposée à la main ne compte pas.
func _noter(chapitre: String) -> void:
	if _libre:
		return
	var f := FileAccess.open(PROGRESSION, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({ "chapitre": chapitre }))


## Le chapitre suivant dans l'ordre de lecture, vide s'il n'y en a plus.
func _chapitre_suivant() -> String:
	var suite: Array = _campagne.get("chapitres", [])
	var i := suite.find(_chapitre)
	if i >= 0 and i + 1 < suite.size():
		return str(suite[i + 1])
	return ""


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
				signature = (signature << 1) | _terrain_en(coin)
			carte.set_cell(Vector2i(x, y), 0, Vector2i(signature, 0))


## Lequel des deux terrains occupe ce sommet de la grille ?
##
## Le terrain 0 est le plus sombre du jeu de tuiles, le 1 l'autre. La salle
## nomme son fond et découpe des zones dedans. La convention est explicite
## depuis Zénor : deviner laquelle des deux teintes est laquelle marchait tant
## qu'un tapis vert s'opposait à du dallage gris, et plus du tout dès qu'on a
## peint de l'herbe contre de la pierre claire.
func _terrain_en(sommet: Vector2i) -> int:
	for zone in _salle.get("zones", []):
		if sommet.x >= int(zone["x"]) and sommet.x <= int(zone["x"]) + int(zone["l"]) \
			and sommet.y >= int(zone["y"]) and sommet.y <= int(zone["y"]) + int(zone["h"]):
			return int(zone.get("terrain", 1))
	return int(_salle.get("fond", 1))


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
	_wellan = Combattant.new()
	_wellan.vie_max = VIE_WELLAN
	_wellan.camp = "ordre"
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

	# Wellan porte sa propre lueur : sans elle, une nuit assez noire pour être
	# une nuit rend le personnage invisible entre deux braseros.
	if _scene.get("ambiance", {}).get("lumieres", false):
		var lueur := PointLight2D.new()
		lueur.texture = _halo(72)
		lueur.color = Color("#dddde4")
		# Wellan est vêtu de noir : sous une nuit assez sombre pour en être une,
		# il disparaît entre deux braseros si sa propre lueur ne le tient pas.
		lueur.energy = 1.4
		_wellan.add_child(lueur)

	_wellan.blesse.connect(func(reste: int, sur: int) -> void: _jauger(reste, sur))
	_wellan.peri.connect(_perdre)


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

## Les étapes du chapitre, la clôture comprise.
##
## `fin` n'est pas un cas à part : c'est la dernière étape, avec sa condition
## comme les autres. La traiter à part obligeait à deux chemins pour la même
## chose, et le chapitre ne pouvait jamais s'achever puisque rien n'attendait
## plus rien.
func _etapes() -> Array:
	var toutes: Array = _scene.get("etapes", []).duplicate()
	var fin: Dictionary = _scene.get("fin", {})
	if not fin.is_empty():
		toutes.append(fin)
	return toutes


func _etape_courante() -> Dictionary:
	var toutes := _etapes()
	return toutes[_etape] if _etape < toutes.size() else {}


func _entrer_dans_l_etape() -> void:
	if _etape >= _etapes().size():
		_achever_le_chapitre()
		return

	var etape := _etape_courante()
	_parles.clear()

	for sortant in etape.get("disparaissent", []):
		_faire_sortir(str(sortant))
	for entrant in etape.get("apparaissent", []):
		_faire_entrer(entrant)

	_objectif.text = str(etape.get("objectif", ""))
	_lever_la_vague(etape)


## Fait débarquer les adversaires de l'étape.
##
## Ils viennent du haut de la carte, côté mer : à Zénor l'ennemi arrive par
## l'eau, et le joueur qui les voit apparaître au même endroit à chaque fois
## comprend d'où vient la menace sans qu'on le lui dise.
func _lever_la_vague(etape: Dictionary) -> void:
	for e in _ennemis:
		if is_instance_valid(e["noeud"]):
			(e["noeud"] as Node).queue_free()
	_ennemis.clear()

	var especes: Dictionary = _scene.get("especes", {})
	var taille := _taille()
	var rang := 0
	for groupe in etape.get("vague", []):
		var espece: Dictionary = especes.get(str(groupe["espece"]), {})
		for n in int(groupe.get("nombre", 1)):
			rang += 1
			var ou := Vector2(
				float(3 + (rang * 5) % (taille.x - 6)) * TUILE,
				float(1 + (rang % 2)) * TUILE)
			_faire_debarquer(str(groupe["espece"]), espece, ou)


func _faire_debarquer(id: String, espece: Dictionary, ou: Vector2) -> void:
	var qui := Combattant.new()
	qui.vie_max = int(espece.get("vie", 3))
	qui.immunise_magie = bool(espece.get("immunise_magie", false))
	qui.position = ou
	add_child(qui)

	# La fiche d'un adversaire est celle de son peuple. Sans planche, il paraît en
	# silhouette de la teinte que la scène lui donne — comme n'importe quel
	# personnage que l'atelier n'a pas encore dessiné.
	var fiche: Dictionary = _monde.get("peuples", {}).get(id, _monde["personnages"].get(id, {}))
	var vue := _sprite_de(fiche)
	if fiche.get("planche") == null:
		vue.modulate = Color(str(espece.get("teinte", "#8b2020")))
	qui.add_child(vue)

	var forme := CollisionShape2D.new()
	var boite := RectangleShape2D.new()
	boite.size = Vector2(12, 8)
	forme.shape = boite
	forme.position = Vector2(0, -4)
	qui.add_child(forme)

	qui.peri.connect(func() -> void:
		_etincelle(qui.global_position + Vector2(0, -10), Color("#d14545"), 0.3)
		qui.queue_free())

	_ennemis.append({
		"noeud": qui,
		"nom": str(espece.get("nom", id)),
		"degats": int(espece.get("degats", 1)),
		"vitesse": float(espece.get("vitesse", 34.0)),
		"prochain": 0.0,
	})


func _vague_debout() -> int:
	var reste := 0
	for e in _ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if qui.vivant():
			reste += 1
	return reste


## Les adversaires marchent sur Wellan et frappent au contact.
func _mener_les_ennemis(delta: float) -> void:
	var maintenant := Time.get_ticks_msec() / 1000.0
	for e in _ennemis:
		if not is_instance_valid(e["noeud"]):
			continue
		var qui: Combattant = e["noeud"]
		if not qui.vivant():
			continue
		var vers: Vector2 = qui.global_position.direction_to(_wellan.global_position)
		var loin: float = qui.global_position.distance_to(_wellan.global_position)
		qui.velocity = vers * float(e["vitesse"]) if loin > 14.0 else Vector2.ZERO
		qui.move_and_slide()
		if loin < 18.0 and maintenant >= float(e["prochain"]):
			e["prochain"] = maintenant + 0.9
			_wellan.encaisser(int(e["degats"]), "fer")


## Le chapitre est joué : on propose la suite, on note où l'on en est.
func _achever_le_chapitre() -> void:
	var suivant := _chapitre_suivant()
	_noter(suivant if suivant != "" else _chapitre)
	_objectif.text = ""

	var mot: Label = _acheve.get_child(0)
	if suivant == "":
		mot.text = "%s\n\nachevé.\n\nC'est tout ce qui est écrit à ce jour." % str(_scene.get("titre", ""))
	else:
		var titre_suivant := str(_lire(DONNEES + "scenes/%s.json" % suivant).get("titre", suivant))
		mot.text = "%s\n\nachevé.\n\nEspace — %s" % [str(_scene.get("titre", "")), titre_suivant]
	_acheve.visible = true


func _perdre() -> void:
	_vaincu = true
	_defaite.visible = true
	_cadre.visible = false
	_invite.visible = false


## Reprendre l'étape : Wellan retrouve son souffle, la vague est relevée.
func _reprendre() -> void:
	_vaincu = false
	_defaite.visible = false
	_wellan.vie = _wellan.vie_max
	_jauger(_wellan.vie, _wellan.vie_max)
	_energie = ENERGIE_MAX
	var depart: Array = _salle.get("depart", [1, 1])
	_wellan.position = Vector2(float(depart[0]) * TUILE, float(depart[1]) * TUILE)
	_lever_la_vague(_etape_courante())


## L'étape est-elle satisfaite par ce qu'on vient d'entendre ?
func _avancer_si_possible() -> void:
	var attend: Dictionary = _etape_courante().get("attend", {})
	if attend.is_empty():
		return

	if attend.has("vague_defaite"):
		if _vague_debout() == 0:
			_etape += 1
			_entrer_dans_l_etape()
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


## La nuit, quand la scène la demande.
##
## Le chapitre 26 place le débarquement dans le noir. Le jouer en plein jour
## vide la moitié du texte de son sens : les fosses qu'on ne voit pas, les feux
## qu'on allume, la vague qui arrive sans qu'on la distingue. Une teinte
## d'ambiance assombrit tout, les braseros y percent des halos.
func _tomber_la_nuit() -> void:
	var ambiance: Dictionary = _scene.get("ambiance", {})
	if ambiance.is_empty():
		return
	var voile := CanvasModulate.new()
	voile.color = Color(str(ambiance.get("teinte", "#ffffff")))
	add_child(voile)


## Un halo, dessiné plutôt que chargé.
##
## Une lumière ponctuelle veut une texture ; en fabriquer une évite de traîner
## un fichier d'image dont personne ne saurait dire à quoi il sert.
func _halo(rayon: int) -> ImageTexture:
	var cote := rayon * 2
	var image := Image.create(cote, cote, false, Image.FORMAT_RGBA8)
	var centre := Vector2(rayon, rayon)
	for y in cote:
		for x in cote:
			var d := centre.distance_to(Vector2(x, y)) / float(rayon)
			var force := clampf(1.0 - d, 0.0, 1.0)
			# Au carré : la lumière d'un feu décroît vite, un dégradé linéaire
			# donne un disque plat qui ne ressemble à rien.
			image.set_pixel(x, y, Color(1, 1, 1, force * force))
	return ImageTexture.create_from_image(image)


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

	if genre == "brasier" and _scene.get("ambiance", {}).get("lumieres", false):
		var feu := PointLight2D.new()
		feu.texture = _halo(96)
		feu.color = Color("#f0d174")
		feu.energy = 1.5
		feu.position = ou
		add_child(feu)


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

	_jauge_vie = _jauge(couche, 8, Color("#8b2020"), Color("#d14545"))
	_jauge_energie = _jauge(couche, 22, Color("#23202e"), Color("#5b9bd8"))

	_defaite = Panel.new()
	_defaite.anchor_left = 0.5
	_defaite.anchor_right = 0.5
	_defaite.anchor_top = 0.5
	_defaite.anchor_bottom = 0.5
	_defaite.offset_left = -130
	_defaite.offset_right = 130
	_defaite.offset_top = -34
	_defaite.offset_bottom = 34
	var deuil := StyleBoxFlat.new()
	deuil.bg_color = Color("#0b0a10")
	deuil.border_color = Color("#8b2020")
	deuil.set_border_width_all(2)
	deuil.set_content_margin_all(10)
	_defaite.add_theme_stylebox_override("panel", deuil)
	_defaite.visible = false
	couche.add_child(_defaite)

	_acheve = Panel.new()
	_acheve.anchor_left = 0.5
	_acheve.anchor_right = 0.5
	_acheve.anchor_top = 0.5
	_acheve.anchor_bottom = 0.5
	_acheve.offset_left = -170
	_acheve.offset_right = 170
	_acheve.offset_top = -54
	_acheve.offset_bottom = 54
	var laurier := StyleBoxFlat.new()
	laurier.bg_color = Color("#0b0a10")
	laurier.border_color = Color("#c08f34")
	laurier.set_border_width_all(2)
	laurier.set_content_margin_all(12)
	_acheve.add_theme_stylebox_override("panel", laurier)
	_acheve.visible = false
	couche.add_child(_acheve)

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


## Une jauge : un fond sombre, une part pleine par-dessus.
func _jauge(couche: CanvasLayer, haut: int, fond: Color, plein: Color) -> ColorRect:
	var creux := ColorRect.new()
	creux.color = fond.darkened(0.5)
	creux.anchor_left = 1.0
	creux.anchor_right = 1.0
	creux.offset_left = -94
	creux.offset_right = -14
	creux.offset_top = haut
	creux.offset_bottom = haut + 8
	couche.add_child(creux)

	var part := ColorRect.new()
	part.color = plein
	part.anchor_right = 1.0
	part.anchor_bottom = 1.0
	creux.add_child(part)
	return part


func _jauger(reste: int, sur: int) -> void:
	_jauge_vie.anchor_right = clampf(float(reste) / float(sur), 0.0, 1.0)


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
	if _acheve.visible:
		if evenement.is_action_pressed("ui_accept"):
			# La progression est déjà notée : recharger la scène rouvre le
			# chapitre suivant sans qu'on ait à transporter d'état.
			get_tree().reload_current_scene()
		return
	if evenement.is_action_pressed("frapper") and not _ouverte and not _vaincu:
		_frapper()
		return
	if evenement.is_action_pressed("lancer") and not _ouverte and not _vaincu:
		_lancer()
		return
	if not evenement.is_action_pressed("ui_accept"):
		return
	if _vaincu:
		_reprendre()
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


## Le coup d'épée.
##
## On interroge l'espace plutôt que de poser une zone le temps d'une image :
## un nœud créé puis détruit à chaque coup laisse la détection à la merci de
## l'ordre des images, et l'on frappe dans le vide une fois sur trois.
func _frapper() -> void:
	var maintenant := Time.get_ticks_msec() / 1000.0
	if maintenant < _prochain_coup:
		return
	_prochain_coup = maintenant + REPOS_EPEE

	var devant := _wellan.global_position + _vers(_direction) * PORTEE_EPEE * 0.7
	var forme := CircleShape2D.new()
	forme.radius = PORTEE_EPEE

	var demande := PhysicsShapeQueryParameters2D.new()
	demande.shape = forme
	demande.transform = Transform2D(0.0, devant)
	demande.collide_with_bodies = true
	for touche in get_world_2d().direct_space_state.intersect_shape(demande, 8):
		var qui = touche.get("collider")
		if qui is Combattant and qui != _wellan:
			qui.encaisser(DEGATS_EPEE, "fer")

	# L'arc part du personnage, non de la zone frappée : c'est le geste qu'on
	# montre, et il doit sortir de la main.
	_jouer_effet("taillade.png", 3, SPRITE, _wellan.global_position + Vector2(0, -10),
		QUART.get(_direction, 0.0), REPOS_EPEE / 4.0, 4.0)


## Le feu de Theandras, déesse protectrice des Chevaliers.
func _lancer() -> void:
	if _energie < COUT_DU_SORT:
		return
	_energie -= COUT_DU_SORT

	var porteur := Node2D.new()
	porteur.position = _wellan.global_position + Vector2(0, -10)
	add_child(porteur)

	# La braise bat en boucle tant que le trait vole : elle ne s'éteint pas au
	# bout de quatre images, elle recommence.
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "feu.png")
	region.region = Rect2(0, 0, 16, 16)
	vue.texture = region
	porteur.add_child(vue)

	var battement := Timer.new()
	battement.wait_time = 0.07
	porteur.add_child(battement)
	# Même raison qu'au-dessus : capture par valeur, donc un dictionnaire.
	var braise := { "image": 0 }
	battement.timeout.connect(func() -> void:
		braise["image"] = (int(braise["image"]) + 1) % 4
		region.region = Rect2(int(braise["image"]) * 16, 0, 16, 16))
	battement.start()

	_traits.append({ "noeud": porteur, "sens": _vers(_direction), "reste": PORTEE_SORT })


func _vers(sens: String) -> Vector2:
	match sens:
		"nord": return Vector2.UP
		"sud": return Vector2.DOWN
		"ouest": return Vector2.LEFT
		_: return Vector2.RIGHT


## L'angle de chaque direction, pour faire pivoter un effet dessiné vers l'est.
##
## Des quarts de tour seulement : à 90 degrés une image de pixel art tourne sans
## perdre un pixel, ce qui ne serait pas vrai d'un angle quelconque.
const QUART := { "est": 0.0, "sud": 90.0, "ouest": 180.0, "nord": 270.0 }


## Joue une petite animation puis s'efface.
##
## Les effets sont des planches d'images côte à côte, comme les personnages :
## on avance la fenêtre, et l'on retire le nœud à la dernière.
func _jouer_effet(planche: String, images: int, cote: int, ou: Vector2,
		angle_deg: float, cadence: float, pivot_x := 0.0) -> Sprite2D:
	var vue := Sprite2D.new()
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + planche)
	region.region = Rect2(0, 0, cote, cote)
	vue.texture = region
	vue.offset = Vector2(cote / 2.0 - pivot_x, 0)
	vue.rotation_degrees = angle_deg
	vue.position = ou
	add_child(vue)

	var minuteur := Timer.new()
	minuteur.wait_time = cadence
	vue.add_child(minuteur)

	# Le compteur vit dans un dictionnaire, non dans une variable.
	#
	# Les fonctions anonymes de GDScript capturent par valeur : incrémenter un
	# entier de l'extérieur ne modifie qu'une copie, et le compte ne monte
	# jamais. Les arcs ne mouraient donc pas — ils s'empilaient, et c'est cet
	# empilement qu'on prenait pour une auréole autour du personnage. Un
	# dictionnaire, lui, se capture par référence.
	var etat := { "image": 0 }
	minuteur.timeout.connect(func() -> void:
		etat["image"] += 1
		if etat["image"] >= images:
			vue.queue_free()
			return
		region.region = Rect2(int(etat["image"]) * cote, 0, cote, cote))
	minuteur.start()
	return vue


func _etincelle(ou: Vector2, teinte: Color, duree: float) -> void:
	# La gerbe d'impact : trois images qui s'ouvrent. La teinte demandée règle
	# l'ardeur, pour distinguer un coup porté d'un adversaire qui tombe.
	var vue := _jouer_effet("eclat.png", 3, 16, ou, 0.0, duree / 3.0)
	vue.modulate = teinte


## Les sorts en vol : on les avance, on regarde ce qu'ils rencontrent.
func _avancer_les_traits(delta: float) -> void:
	for i in range(_traits.size() - 1, -1, -1):
		var trait_ = _traits[i]
		var porteur: Node2D = trait_["noeud"]
		if not is_instance_valid(porteur):
			_traits.remove_at(i)
			continue

		var pas: float = VITESSE_SORT * delta
		porteur.position += trait_["sens"] * pas
		trait_["reste"] -= pas

		var atteint := false
		for e in _ennemis:
			if not is_instance_valid(e["noeud"]):
				continue
			var qui: Combattant = e["noeud"]
			if not qui.vivant():
				continue
			if porteur.position.distance_to(qui.global_position + Vector2(0, -10)) < 12.0:
				# La carapace refuse le sort : `encaisser` rend faux, et le trait
				# poursuit sa course au lieu de s'éteindre. Le joueur voit que ça
				# ne prend pas.
				if qui.encaisser(DEGATS_SORT, "magie"):
					_etincelle(porteur.position, Color("#ffffff"), 0.21)
					atteint = true
					break

		if atteint or trait_["reste"] <= 0.0:
			porteur.queue_free()
			_traits.remove_at(i)


func _physics_process(delta: float) -> void:
	_energie = minf(_energie + REGAIN * delta, ENERGIE_MAX)
	_jauge_energie.anchor_right = _energie / ENERGIE_MAX
	_choisir_l_interlocuteur()

	if _vaincu:
		_wellan.velocity = Vector2.ZERO
		return

	_avancer_les_traits(delta)

	# Les adversaires attendent la fin de l'échange : être mordu pendant qu'on
	# lit une réplique qu'on ne peut pas interrompre serait une punition sans
	# recours.
	if not _ouverte and not _acheve.visible:
		_mener_les_ennemis(delta)
		_avancer_si_possible()

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


## Joue le chapitre courant jusqu'à sa clôture, puis passe au suivant.
##
## L'épreuve de la campagne n'est pas qu'un chapitre se joue — c'est qu'il en
## appelle un autre, et que la partie se retrouve où on l'avait laissée.
func _capturer() -> void:
	print("CHAPITRE %s — %s" % [_chapitre, _scene.get("titre", "")])
	await _garder("00-%s" % _chapitre, 12)

	var garde := 0
	while not _acheve.visible and garde < 40:
		garde += 1
		var etape := _etape_courante()
		var attend: Dictionary = etape.get("attend", {})

		if attend.has("parler"):
			await _parler_a(str(attend["parler"]), "%02d-%s" % [garde, attend["parler"]])
		elif attend.has("parler_tous"):
			for id in attend["parler_tous"]:
				await _parler_a(str(id), "%02d-%s" % [garde, id])
		elif attend.has("vague_defaite"):
			# On abat la vague par le modèle : la mêlée a été éprouvée ailleurs,
			# ici c'est l'enchaînement des chapitres qu'on vérifie.
			for e in _ennemis:
				if not is_instance_valid(e["noeud"]):
					continue
				var qui: Combattant = e["noeud"]
				while is_instance_valid(qui) and qui.vivant():
					qui.encaisser(99, "fer")
					await _attendre(30)
			await _attendre(20)
		else:
			break
		print("  → %s" % (_objectif.text if _objectif.text != "" else "(clôture)"))

	if _acheve.visible:
		var mot: Label = _acheve.get_child(0)
		print("ACHEVE : %s" % mot.text.replace("\n", " "))
	else:
		print("PAS ACHEVE après %d tours, étape %d" % [garde, _etape])

	get_tree().quit()


## Regarde les effets, image par image.
##
## On les prend pendant qu'ils jouent, non après : une animation captée à sa
## fin ne montre que le vide qu'elle laisse. C'est la même faute que la boîte de
## dialogue photographiée une fois fermée.
func _capturer_les_effets() -> void:
	await _attendre(20)
	if _vague_debout() == 0 and not _ennemis.is_empty():
		pass

	# La taillade, dans les quatre directions.
	for sens in ["sud", "est", "nord", "ouest"]:
		# Une prise par direction, bien séparée : trop rapprochées, l'arc
		# précédent traîne encore et l'on croit voir un anneau.
		await _attendre(40)
		_direction = sens
		_prochain_coup = 0.0
		_frapper()
		await _attendre(5)
		var lames := 0
		for enfant in get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				var at: AtlasTexture = enfant.texture
				if str(at.atlas.resource_path).ends_with("taillade.png"):
					lames += 1
		print("  %s : %d lame(s) à l'écran" % [sens, lames])
		get_viewport().get_texture().get_image().save_png("res://capture-taillade-%s.png" % sens)
	print("TAILLADE dans quatre sens")

	# La boule de feu en vol, puis son éclat.
	_direction = "est"
	_energie = ENERGIE_MAX
	_lancer()
	for n in 3:
		await _attendre(9)
		get_viewport().get_texture().get_image().save_png("res://capture-feu-%d.png" % n)
	print("FEU %d trait(s) en vol" % _traits.size())

	_etincelle(_wellan.global_position + Vector2(28, -10), Color("#ffffff"), 0.3)
	await _attendre(4)
	get_viewport().get_texture().get_image().save_png("res://capture-eclat.png")
	print("ECLAT")

	get_tree().quit()


func _touche(action: String) -> void:
	var t := InputEventAction.new()
	t.action = action
	t.pressed = true
	Input.parse_input_event(t)


func _attendre(images: int) -> void:
	for i in images:
		await get_tree().process_frame


## Aborde un personnage et l'écoute jusqu'au bout.
func _parler_a(id: String, nom_image: String) -> void:
	if not _habitants.has(id):
		print("ABSENT %s" % id)
		return
	_wellan.global_position = _habitants[id].position + Vector2(0, TUILE)
	# On attend que la zone réagisse au lieu de compter les images : au
	# démarrage, la compilation des shaders affame la physique et un nombre fixe
	# d'images ne garantit rien.
	var patience := 0
	while _proche != id and patience < 120:
		await get_tree().process_frame
		patience += 1
	if _proche != id:
		print("HORS DE PORTEE %s (proche=%s)" % [id, _proche])
		return

	var pages := 0
	while pages < 12:
		_touche("ui_accept")
		await _attendre(2)
		pages += 1
		if pages == 2 and _ouverte:
			get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom_image)
		if not _ouverte and pages > 1:
			break
	print("PARLE %s en %d pages" % [id, pages])


func _garder(nom: String, images: int) -> void:
	await _attendre(images)
	get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)
