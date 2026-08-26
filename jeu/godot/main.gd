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
const TAILLADE := 64
const PORTRAIT := 84          ## côté du visage dans la boîte de dialogue          ## côté d'une image d'arc, plus large que le sprite
## Un pas un peu plus vif. À cinquante-huit, traverser une salle de vingt-six
## tuiles demandait sept secondes, et l'on sentait la longueur avant de sentir
## le lieu.
const VITESSE := 80.0
const CADENCE := 7.0

## Rangée de la planche pour chaque direction regardée.
const RANGEE := { "sud": 0, "nord": 1, "ouest": 2, "est": 3 }

const DONNEES := "res://donnees/"
const PARTIES := "user://parties.json"
const PARTIES_ESSAI := "user://parties-essai.json"

## Le combat, en clair. Ces nombres sont à nous ; ce qui vient du texte, c'est
## que la carapace des hommes-insectes boit la magie.
const VIE_WELLAN := 8
const ENERGIE_MAX := 100.0
const COUT_DU_SORT := 25.0
const REGAIN := 14.0          ## énergie par seconde
const REPOS_EPEE := 0.38      ## secondes entre deux coups
## Jusqu'où porte le fer, et la demi-largeur du balayage.
##
## La zone couvrait autrefois de sept pixels derrière Wellan à trente-sept
## devant, pendant que l'arc dessiné n'en atteignait que dix-neuf. On frappait
## donc ce qu'on ne voyait pas atteindre, et le coup paraissait court — un
## joueur juge la portée sur ce qu'il voit, non sur ce qui touche.
##
## Les deux valeurs sont relevées sur l'arc lui-même — de quinze à trente-sept
## pixels devant Wellan, et plus rien derrière. Ce qu'on voit est ce qui touche.
const PORTEE_EPEE := 37.0
const LARGEUR_COUP := 11.0
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
var _ouverture: Panel

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
## Une page sait de quel genre elle est.
##
## Une parole et une description ne se lisent pas de la même façon : l'une sort
## d'une bouche, l'autre est ce que le joueur constate. Les confondre dans un
## même cadre effaçait la différence, et les maladresses des personnages — qui
## font le sel de ces échanges — se perdaient dans la narration.
var _pages: Array = []
var _page := 0
var _ouverte := false

var _cadre: Panel
var _texte: RichTextLabel
var _invite: Label
var _bandeau: Panel          ## les descriptions, distinctes des paroles
var _recit: RichTextLabel
var _visage: TextureRect     ## le portrait de qui parle
var _marcheurs: Array = []   ## ceux qui entrent ou sortent, en chemin
var _bulles := {}            ## les bulles de parole, par identifiant de fiche
var _objets := {}            ## ce qu'on peut examiner, par clé
var _cloture_dite := false
var _flottement := 0.0
var _pause: Panel
var _menu: RichTextLabel
var _choix_pause := 0
var _en_pause := false
var _recit_capture := false   ## une seule image de description suffit au contrôle
var _invite_capture := false
var _bulles_capture := false
var _mare: Sprite2D = null    ## la mare de sang, gardée entre deux morts


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
	_annoncer_le_chapitre()

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
	for nom in [["frapper", KEY_J], ["lancer", KEY_K], ["pause", KEY_ESCAPE]]:
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
	var repris: String = str(_partie().get("chapitre", ""))
	if repris != "" and suite.has(repris):
		return str(repris)
	return str(suite[0]) if not suite.is_empty() else "i-01"


## Note où l'on en est. Une scène imposée à la main ne compte pas.
func _noter(chapitre: String) -> void:
	if _libre:
		return
	var carnet := _lire(_carnet())
	if not carnet.has("parties"):
		carnet = { "courante": 0, "parties": [null, null, null] }
	var n := int(carnet.get("courante", 0))
	var parties: Array = carnet["parties"]
	if n >= 0 and n < parties.size():
		parties[n] = { "chapitre": chapitre }
	var f := FileAccess.open(_carnet(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(carnet))


## Le chapitre suivant dans l'ordre de lecture, vide s'il n'y en a plus.
func _chapitre_suivant() -> String:
	var suite: Array = _campagne.get("chapitres", [])
	var i := suite.find(_chapitre)
	if i >= 0 and i + 1 < suite.size():
		return str(suite[i + 1])
	return ""


## Où se note la partie.
##
## Un test ne joue pas la partie du joueur, mais il doit tout de même éprouver
## l'enchaînement — sans quoi on ne vérifie plus ce qu'on livre. Il tient donc
## son propre carnet.
##
## Le mode capture écrivait dans le même fichier que la partie : à force de
## vérifier la campagne, la sauvegarde s'est trouvée poussée jusqu'au dernier
## chapitre, et le jeu s'ouvrait sur la bataille de Zénor comme si toute
## l'histoire qui précède avait été jouée.
func _carnet() -> String:
	var arguments := OS.get_cmdline_user_args()
	if OS.get_cmdline_args().has("--capture") or arguments.has("--capture") or arguments.has("--effets"):
		return PARTIES_ESSAI
	return PARTIES


## L'emplacement en cours, et ce qu'il contient.
func _partie() -> Dictionary:
	var carnet := _lire(_carnet())
	var parties: Array = carnet.get("parties", [])
	var n := int(carnet.get("courante", 0))
	if n < 0 or n >= parties.size() or parties[n] == null:
		return {}
	return parties[n]


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
	# Le sol occupe son propre plan, sous tout le reste. Cela libère un plan
	# intermédiaire pour ce qui se pose au sol sans être un personnage — une
	# mare de sang, demain une empreinte ou une ombre.
	carte.z_index = -2
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
		_faire_entrer(habitant, false)
	for objet in _salle.get("objets", []):
		_batir_objet(objet)


## Le bord de la salle le plus proche d'une case, une tuile au-delà.
##
## C'est par là qu'on entre et qu'on sort quand la scène ne le dit pas : on
## vient du dehors le plus proche, ce qui est presque toujours ce qu'on veut.
func _seuil(place: Vector2i) -> Vector2i:
	var taille := _taille()
	var vers := {
		Vector2i(place.x, -1): place.y,
		Vector2i(place.x, taille.y): taille.y - 1 - place.y,
		Vector2i(-1, place.y): place.x,
		Vector2i(taille.x, place.y): taille.x - 1 - place.x,
	}
	var meilleur := Vector2i(place.x, -1)
	var court := 1 << 30
	for porte in vers:
		if vers[porte] < court:
			court = vers[porte]
			meilleur = porte
	return meilleur


func _faire_entrer(habitant: Dictionary, en_marchant := true) -> void:
	var id := str(habitant["fiche"])
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	if fiche.is_empty():
		push_warning("Fiche inconnue : %s" % id)
		return
	if _habitants.has(id):
		return

	var place := Vector2i(int(habitant["x"]), int(habitant["y"]))
	var arrivee := Vector2(place) * TUILE

	# Qui arrive pendant la scène entre en marchant, depuis le seuil que la
	# scène désigne ou, à défaut, depuis le bord le plus proche. Un personnage
	# qui apparaît d'un coup au milieu de la salle se lit comme un défaut.
	var depart := arrivee
	if en_marchant:
		var seuil := _seuil(place)
		if habitant.has("depuis"):
			seuil = Vector2i(int(habitant["depuis"][0]), int(habitant["depuis"][1]))
		depart = Vector2(seuil) * TUILE

	var corps := StaticBody2D.new()
	corps.position = depart
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
	if en_marchant and depart != arrivee:
		_marcheurs.append({ "corps": corps, "vue": vue, "cible": arrivee, "phase": 0.0, "sortir": false })


## Il s'en va comme il est venu : à pied, jusqu'au seuil le plus proche.
func _faire_sortir(id: String, en_marchant := true) -> void:
	if not _habitants.has(id):
		return
	_a_portee.erase(id)
	if _proche == id:
		_proche = ""
		_invite.visible = false

	var corps: Node2D = _habitants[id]
	_habitants.erase(id)

	if not en_marchant:
		corps.queue_free()
		return

	var vue: Sprite2D = null
	for enfant in corps.get_children():
		if enfant is Sprite2D:
			vue = enfant
			break
	if vue == null:
		corps.queue_free()
		return

	var place := Vector2i(corps.position / float(TUILE))
	_marcheurs.append({
		"corps": corps, "vue": vue,
		"cible": Vector2(_seuil(place)) * TUILE, "phase": 0.0, "sortir": true,
	})


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
	_rafraichir_les_bulles()
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
## Annonce le chapitre : son rang dans la campagne, son titre, sa source.
func _annoncer_le_chapitre() -> void:
	var suite: Array = _campagne.get("chapitres", [])
	var rang := suite.find(_chapitre) + 1
	var mot: RichTextLabel = _ouverture.get_child(0)

	# Tailles relevées d'un tiers avec le viewport : à 640×360, une police réglée
	# pour 270 pixels de haut se lit deux fois plus petite qu'avant.
	var entete := "Chapitre %d sur %d" % [rang, suite.size()] if rang > 0 else "Hors campagne"
	# La référence au tome et au chapitre a été retirée : elle parle du livre au
	# joueur, là où tout le reste lui parle du monde.
	mot.text = "[center][font_size=14][color=#a6a8b2]%s[/color][/font_size]\n\n[b][color=#f0d174]%s[/color][/b]\n\n[font_size=14][color=#a6a8b2]Espace[/color][/font_size][/center]" % [
		entete, str(_scene.get("titre", _chapitre))]
	_ouverture.visible = true


func _achever_le_chapitre() -> void:
	# Le mot de la fin d'abord, l'écran de fin ensuite : on referme le chapitre
	# avant d'annoncer qu'il est refermé.
	var mot_final: Array = _scene.get("cloture", [])
	if not _cloture_dite and not mot_final.is_empty():
		_cloture_dite = true
		_objectif.text = ""
		_reciter(mot_final)
		return

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


## Wellan tombe.
##
## Un panneau qui s'affiche pendant que le personnage reste debout ne dit pas
## qu'il est mort, il dit que la partie s'arrête. Le sprite bascule donc au sol
## et une mare s'élargit sous lui — c'est ce qu'on voit qui doit porter la
## nouvelle, non le texte par-dessus.
func _perdre() -> void:
	_vaincu = true
	_defaite.visible = true
	_cadre.visible = false
	_bandeau.visible = false
	_invite.visible = false

	_vue.rotation_degrees = 90.0
	_vue.offset = Vector2(0, -8)

	if _mare == null:
		_mare = Sprite2D.new()
		var region := AtlasTexture.new()
		region.atlas = load(DONNEES + "sang.png")
		region.region = Rect2(0, 0, SPRITE, SPRITE)
		_mare.texture = region
		# Entre le sol et les corps.
		#
		# Le tri par profondeur ne sait mettre une chose que *derrière* une
		# autre, jamais dessous : posée assez haut pour passer derrière Wellan,
		# la mare lui coiffait la tête comme un capuchon rouge. Un plan
		# intermédiaire règle ce que l'ordre en y ne peut pas exprimer.
		_mare.z_index = -1
		add_child(_mare)
	# Sur la ligne de sol, sous le corps couché qui s'étend à droite des pieds.
	# Mesuré : à moins sept, la mare occupait y 101 à 132 quand le corps
	# commençait à 133 — elles ne se touchaient pas.
	_mare.position = _wellan.global_position + Vector2(9, -1)
	_mare.visible = true
	_elargir_la_mare()


## La mare s'élargit en trois temps.
func _elargir_la_mare() -> void:
	var region: AtlasTexture = _mare.texture
	for n in 3:
		if not _vaincu:
			return
		region.region = Rect2(n * SPRITE, 0, SPRITE, SPRITE)
		await get_tree().create_timer(0.16).timeout


## Reprendre l'étape : Wellan retrouve son souffle, la vague est relevée.
func _reprendre() -> void:
	_vaincu = false
	_defaite.visible = false
	_vue.rotation_degrees = 0.0
	_vue.offset = Vector2(0, -SPRITE / 2.0 + 2)
	if _mare != null:
		_mare.visible = false
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


## Un objet du décor, et ce qu'on en dit quand on s'en approche.
##
## Un décor muet n'est qu'un motif. Une torche qu'on peut regarder de près, un
## trône dont on lit l'histoire, une bannière qu'on reconnaît : c'est ce qui
## fait qu'une salle cesse d'être un couloir entre deux dialogues.
func _batir_objet(objet: Dictionary) -> void:
	var genre := str(objet.get("type", ""))
	var ou := Vector2(float(objet["x"]) * TUILE, float(objet["y"]) * TUILE)
	_dessiner_objet(genre, ou, objet)

	var texte: Array = objet.get("texte", [])
	if texte.is_empty():
		return

	# Une clé propre à l'objet : `_proche` désigne indifféremment une fiche ou
	# une chose, et il faut pouvoir les distinguer.
	var cle := "objet:%d:%d" % [int(objet["x"]), int(objet["y"])]
	_objets[cle] = { "nom": str(objet.get("nom", "")), "texte": texte }

	var socle := Node2D.new()
	socle.position = ou
	add_child(socle)
	_zone_de_parole(socle, cle)
	_habitants[cle] = socle


## Les sortes de mobilier, dans l'ordre de la planche `objets.png`.
const MOBILIER := ["brasier", "banniere", "coffre", "trone", "stele", "autel", "tombe", "feu"]

func _dessiner_objet(genre: String, ou: Vector2, objet: Dictionary) -> void:
	# Une silhouette par sorte, tirée d'une planche dessinée par calcul.
	#
	# Le premier jet peignait le même carré coloré pour tout : un trône, une
	# bannière et un coffre s'y ressemblaient, et un décor où tout est le même
	# carré ne se regarde pas deux fois.
	#
	# En Sprite2D et non en ColorRect : un Control ne participe pas au tri par
	# profondeur et se dessine dans l'ordre de l'arbre.
	var vue := Sprite2D.new()
	var n := MOBILIER.find(genre)
	var region := AtlasTexture.new()
	region.atlas = load(DONNEES + "objets.png")
	region.region = Rect2(maxi(n, 0) * TUILE, 0, TUILE, TUILE)
	vue.texture = region
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
	couche.add_child(_cadre)

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
	couche.add_child(_invite)

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
	couche.add_child(_bandeau)

	_recit = RichTextLabel.new()
	_recit.bbcode_enabled = true
	_recit.anchor_right = 1.0
	_recit.anchor_bottom = 1.0
	_recit.offset_left = 24
	_recit.offset_right = -24
	_recit.scroll_active = false
	_recit.add_theme_font_size_override("normal_font_size", 15)
	_recit.add_theme_font_size_override("italics_font_size", 15)
	_bandeau.add_child(_recit)

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
	couche.add_child(_pause)

	_menu = RichTextLabel.new()
	_menu.bbcode_enabled = true
	_menu.anchor_right = 1.0
	_menu.anchor_bottom = 1.0
	_menu.scroll_active = false
	_menu.add_theme_font_size_override("normal_font_size", 15)
	_menu.add_theme_font_size_override("bold_font_size", 15)
	_pause.add_child(_menu)

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
	couche.add_child(_objectif)

	_jauge_vie = _jauge(couche, 8, Color("#8b2020"), Color("#d14545"))
	_jauge_energie = _jauge(couche, 22, Color("#23202e"), Color("#5b9bd8"))

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
	couche.add_child(_defaite)

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
	couche.add_child(_ouverture)

	var titre := RichTextLabel.new()
	titre.bbcode_enabled = true
	titre.anchor_right = 1.0
	titre.anchor_bottom = 1.0
	titre.scroll_active = false
	titre.add_theme_font_size_override("normal_font_size", 15)
	titre.add_theme_font_size_override("bold_font_size", 18)
	_ouverture.add_child(titre)

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


## Le personnage se tourne vers celui qui l'aborde.
##
## Parler au dos de quelqu'un est ce qui trahissait le plus que ces gens sont
## des décors posés : le Roi répondait à Wellan sans le regarder. Il suffit de
## reprendre la rangée de sa planche selon l'axe qui les sépare — celui des deux
## écarts qui domine, comme pour la marche.
##
## Il garde ensuite cette orientation. Un personnage qui reprendrait sa pose
## d'origine sitôt la conversation finie aurait l'air de se détourner.
func _tourner_vers_moi(id: String) -> void:
	if id.begins_with("objet:"):
		return
	if not _habitants.has(id):
		return
	var corps: Node2D = _habitants[id]
	var vue: Sprite2D = null
	for enfant in corps.get_children():
		if enfant is Sprite2D:
			vue = enfant
			break
	if vue == null or not (vue.texture is AtlasTexture):
		return

	var ecart := _wellan.global_position - corps.global_position
	var sens := "sud"
	if absf(ecart.x) > absf(ecart.y):
		sens = "est" if ecart.x > 0.0 else "ouest"
	else:
		sens = "sud" if ecart.y > 0.0 else "nord"

	var region: AtlasTexture = vue.texture
	region.region = Rect2(region.region.position.x, RANGEE[sens] * SPRITE, SPRITE, SPRITE)


## Ce que dit un personnage.
##
## La scène en cours d'abord : si le chapitre lui a écrit des répliques pour
## cette étape, ce sont celles-là. Sa fiche à défaut — de sorte qu'aucun
## personnage ne soit jamais muet, même ajouté à la dernière minute et sans une
## ligne écrite pour lui.
func _repliques(id: String) -> Array:
	var ecrites: Dictionary = _etape_courante().get("dialogues", {})
	if ecrites.has(id):
		var pages := []
		for ligne in ecrites[id]:
			var qui := str(ligne.get("qui", ""))
			var dit := str(ligne.get("dit", ""))
			if qui == "recit":
				pages.append({ "genre": "recit", "texte": dit })
			else:
				var nom := str(_monde["personnages"].get(qui, {}).get("nom", qui))
				pages.append({ "genre": "parole", "qui": qui, "nom": nom, "texte": dit })
		return pages
	return _fiche_en_repliques(id)


## Le pis-aller : ce que la fiche du Codex permet de dire.
## Le pis-aller : ce que la fiche du Codex permet de dire.
##
## Ce n'est pas une parole — le personnage ne récite pas son rôle. C'est ce que
## Wellan sait de lui, donc une description.
##
## Le décompte des volumes a été retiré : dire « paraît dans 43 des 44 volumes »
## parle du livre au joueur, non du monde au personnage, et rompt tout ce que la
## scène venait d'établir.
func _fiche_en_repliques(id: String) -> Array:
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	var nom := str(fiche.get("nom", id))
	var pages := [{ "genre": "recit", "texte": "%s. %s" % [nom, fiche.get("role", "")] }]

	var liens: Array = fiche.get("liens", [])
	if not liens.is_empty():
		var dits := PackedStringArray()
		for lien in liens.slice(0, 2):
			# Le Codex empile les nuances d'un lien en les séparant par des
			# points-virgules. Tout dire ferait de la réplique une fiche ; on
			# garde la première nuance, qui est la plus générale.
			var nature := str(lien["nature"]).split(";")[0].strip_edges()
			dits.append("%s — %s" % [lien["nom"], nature])
		pages.append({ "genre": "recit", "texte": "\n".join(dits) })
	return pages


func _afficher() -> void:
	if _page >= _pages.size():
		_ouverte = false
		_cadre.visible = false
		_bandeau.visible = false
		_invite.visible = _proche != ""
		# On ne compte l'échange que s'il a été mené jusqu'au bout : entamer une
		# conversation et s'en aller ne fait pas avancer le chapitre.
		if _interlocuteur != "":
			_parles[_interlocuteur] = true
			_interlocuteur = ""
			_avancer_si_possible()
			_rafraichir_les_bulles()
		elif _cloture_dite and not _acheve.visible:
			# La clôture vient de se terminer : l'écran de fin peut paraître.
			_achever_le_chapitre()
		return
	var page: Dictionary = _pages[_page]
	if str(page.get("genre", "parole")) == "recit":
		_cadre.visible = false
		_bandeau.visible = true
		_recit.text = "[center][i][color=#dddde4]%s[/color][/i][/center]" % str(page.get("texte", ""))
	else:
		_bandeau.visible = false
		_cadre.visible = true
		_montrer_le_visage(str(page.get("qui", "")))
		_texte.text = "[b][color=#f0d174]%s[/color][/b]\n%s" % [
			str(page.get("nom", "")), str(page.get("texte", ""))]


## Récite une suite de descriptions.
##
## Ni parole ni personnage : c'est la voix qui pose un chapitre et celle qui le
## referme. Elle emprunte le même mécanisme de pages, avec le genre « recit »,
## donc le bandeau large et l'italique — ce que le joueur lit, non ce qu'on lui
## dit.
func _reciter(lignes: Array) -> void:
	if lignes.is_empty():
		return
	_pages = []
	for l in lignes:
		_pages.append({ "genre": "recit", "texte": str(l) })
	_page = 0
	_interlocuteur = ""
	_ouverte = true
	_invite.visible = false
	_afficher()


## Montre le portrait de qui parle, et décale le texte pour lui faire place.
func _montrer_le_visage(id: String) -> void:
	var fiche: Dictionary = _monde["personnages"].get(id, {})
	var visage = fiche.get("portrait")
	if visage == null:
		_visage.visible = false
		_texte.offset_left = 10
		return
	_visage.texture = load("res://assets/" + str(visage))
	_visage.visible = true
	_texte.offset_left = 10 + PORTRAIT + 8


const CHOIX_PAUSE := ["Reprendre", "Sauvegarder", "Écran-titre"]

func _dessiner_la_pause(mot := "") -> void:
	var lignes := PackedStringArray(["[center][color=#a6a8b2]Pause[/color][/center]", ""])
	for i in CHOIX_PAUSE.size():
		var vise := i == _choix_pause
		lignes.append("[center]%s[/center]" % (
			"[color=#f0d174]▸ %s ◂[/color]" % CHOIX_PAUSE[i] if vise
			else "[color=#71727e]%s[/color]" % CHOIX_PAUSE[i]))
	if mot != "":
		lignes.append("")
		lignes.append("[center][color=#43c47f]%s[/color][/center]" % mot)
	_menu.text = "\n".join(lignes)


func _basculer_la_pause() -> void:
	_en_pause = not _en_pause
	_pause.visible = _en_pause
	_choix_pause = 0
	if _en_pause:
		_wellan.velocity = Vector2.ZERO
		_dessiner_la_pause()


func _choisir_dans_la_pause() -> void:
	match _choix_pause:
		0:
			_basculer_la_pause()
		1:
			_noter(_chapitre)
			_dessiner_la_pause("Partie notée.")
		2:
			get_tree().change_scene_to_file("res://titre.tscn")


## Qui a quelque chose à dire qu'on n'a pas encore entendu.
##
## Seule la parole écrite par la scène compte. Une fiche du Codex se lit comme
## une description et reste disponible indéfiniment : la signaler mettrait une
## bulle sur les trois cent soixante-cinq personnages du monde, ce qui ne
## voudrait plus rien dire.
func _a_dire(id: String) -> bool:
	if id.begins_with("objet:"):
		return false
	if _parles.has(id):
		return false
	return (_etape_courante().get("dialogues", {}) as Dictionary).has(id)


func _rafraichir_les_bulles() -> void:
	for id in _habitants:
		var doit := _a_dire(str(id))
		if doit and not _bulles.has(id):
			var corps: Node2D = _habitants[id]
			var bulle := Sprite2D.new()
			bulle.texture = load(DONNEES + "bulle.png")
			bulle.position = Vector2(0, -38)
			corps.add_child(bulle)
			_bulles[id] = bulle
		elif not doit and _bulles.has(id):
			if is_instance_valid(_bulles[id]):
				_bulles[id].queue_free()
			_bulles.erase(id)

	# Ceux qui ont quitté la salle emportent la leur.
	for id in _bulles.keys():
		if not _habitants.has(id):
			if is_instance_valid(_bulles[id]):
				_bulles[id].queue_free()
			_bulles.erase(id)


func _unhandled_input(evenement: InputEvent) -> void:
	# La pause passe avant tout : on doit pouvoir s'arrêter au milieu d'une
	# réplique comme au milieu d'une mêlée.
	if evenement.is_action_pressed("pause") and not _ouverture.visible and not _acheve.visible:
		_basculer_la_pause()
		return
	if _en_pause:
		if evenement.is_action_pressed("ui_down"):
			_choix_pause = (_choix_pause + 1) % CHOIX_PAUSE.size()
			_dessiner_la_pause()
		elif evenement.is_action_pressed("ui_up"):
			_choix_pause = (_choix_pause + CHOIX_PAUSE.size() - 1) % CHOIX_PAUSE.size()
			_dessiner_la_pause()
		elif evenement.is_action_pressed("ui_accept"):
			_choisir_dans_la_pause()
		return

	if _ouverture.visible:
		if evenement.is_action_pressed("ui_accept"):
			_ouverture.visible = false
			_reciter(_scene.get("ouverture", []))
		return
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
	elif _proche.begins_with("objet:"):
		var chose: Dictionary = _objets.get(_proche, {})
		var lignes: Array = chose.get("texte", [])
		var nom := str(chose.get("nom", ""))
		if nom != "":
			lignes = [nom] + lignes
		_reciter(lignes)
		return
	elif _proche != "":
		_interlocuteur = _proche
		_pages = _repliques(_proche)
		_page = 0
		_ouverte = true
		_invite.visible = false
		_tourner_vers_moi(_proche)
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

	var devant := _wellan.global_position + _vers(_direction) * (PORTEE_EPEE - LARGEUR_COUP)
	var forme := CircleShape2D.new()
	forme.radius = LARGEUR_COUP

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
	_jouer_effet("taillade.png", 3, TAILLADE, _wellan.global_position + Vector2(0, -10),
		QUART.get(_direction, 0.0), REPOS_EPEE / 4.0, 8.0)


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


## Fait avancer ceux qui entrent ou qui s'en vont.
func _avancer_les_marcheurs(delta: float) -> void:
	for i in range(_marcheurs.size() - 1, -1, -1):
		var m: Dictionary = _marcheurs[i]
		var corps = m["corps"]
		if not is_instance_valid(corps):
			_marcheurs.remove_at(i)
			continue

		var reste: Vector2 = m["cible"] - corps.position
		if reste.length() <= 2.0:
			corps.position = m["cible"]
			if m["sortir"]:
				corps.queue_free()
			else:
				_poser(m["vue"], 0, _sens_de(reste))
			_marcheurs.remove_at(i)
			continue

		# Un peu moins vif que Wellan : il marche, il ne le course pas.
		corps.position += reste.normalized() * VITESSE * 0.75 * delta
		m["phase"] = fmod(m["phase"] + delta * CADENCE, 4.0)
		_poser(m["vue"], int(m["phase"]), _sens_de(reste))


## Le sens dominant d'un déplacement.
func _sens_de(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "est" if v.x > 0.0 else "ouest"
	return "sud" if v.y > 0.0 else "nord"


## Pose une image de planche sur un sprite.
func _poser(vue, colonne: int, sens: String) -> void:
	if vue == null or not (vue.texture is AtlasTexture):
		return
	var region: AtlasTexture = vue.texture
	region.region = Rect2(colonne * SPRITE, RANGEE[sens] * SPRITE, SPRITE, SPRITE)


func _physics_process(delta: float) -> void:
	if _en_pause:
		_wellan.velocity = Vector2.ZERO
		return

	# Les bulles montent et descendent doucement : immobiles elles se prennent
	# pour un élément du décor, et l'œil cesse de les voir.
	_flottement += delta * 3.0
	var hauteur := -38.0 + sin(_flottement) * 2.0
	for id in _bulles:
		if is_instance_valid(_bulles[id]):
			_bulles[id].position.y = hauteur

	# Avant tout le reste : ceux qui entrent ou s'en vont avancent même pendant
	# un dialogue ou le carton d'ouverture. Une arrivée qui se fige parce qu'on
	# lit une réplique se verrait aussitôt.
	_avancer_les_marcheurs(delta)

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
	# Le carton d'abord : c'est la première chose que voit un joueur, donc la
	# première qu'il faut regarder.
	await _attendre(6)
	get_viewport().get_texture().get_image().save_png("res://capture-carton.png")
	_ouverture.visible = false

	# La narration d'ouverture, que le carton enchaîne pour un joueur.
	_reciter(_scene.get("ouverture", []))
	if _ouverte:
		await _attendre(4)
		get_viewport().get_texture().get_image().save_png("res://capture-ouverture.png")
		print("OUVERTURE %d page(s)" % _pages.size())
		while _ouverte:
			_touche("ui_accept")
			await _attendre(2)

	# Une vue d'ensemble de la salle, mobilier compris : on ne vérifie pas un
	# décor sur une capture centrée à deux tuiles du personnage.
	var taille := _taille()
	_wellan.global_position = Vector2(taille) * TUILE / 2.0
	await _attendre(8)
	get_viewport().get_texture().get_image().save_png("res://capture-salle.png")

	# Un objet du décor : il faut pouvoir le regarder de près.
	var chose := ""
	for cle in _objets:
		chose = str(cle)
		break
	if chose != "":
		_wellan.global_position = _habitants[chose].position + Vector2(0, TUILE)
		var patience := 0
		while _proche != chose and patience < 90:
			await get_tree().process_frame
			patience += 1
		if _proche == chose:
			_touche("ui_accept")
			await _attendre(4)
			get_viewport().get_texture().get_image().save_png("res://capture-objet.png")
			print("OBJET %s — %s" % [chose, _objets[chose]["nom"]])
			while _ouverte:
				_touche("ui_accept")
				await _attendre(2)
		else:
			print("OBJET hors de portée : %s" % chose)

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

	await _eprouver_les_orientations()

	# La pause : on doit pouvoir s'arrêter, et voir où l'on s'arrête.
	#
	# On écarte d'abord l'écran de fin de chapitre : tant qu'il est là, la pause
	# est ignorée — à raison — et l'appui suivant rechargerait la scène, ce qui
	# laisserait la capture sans viewport.
	_acheve.visible = false
	_touche("pause")
	await _attendre(6)
	get_viewport().get_texture().get_image().save_png("res://capture-pause.png")
	print("PAUSE ouverte=%s choix=%s" % [_en_pause, CHOIX_PAUSE[_choix_pause]])
	_touche("ui_down")
	await _attendre(3)
	_touche("ui_accept")
	await _attendre(6)
	get_viewport().get_texture().get_image().save_png("res://capture-pause-note.png")
	print("PAUSE après sauvegarde : %s" % _partie())

	# « Sauvegarder » note le chapitre en cours — ce qui, ici, écrase l'avance
	# que la fin du chapitre venait d'inscrire. Le banc remet donc la partie où
	# le chapitre l'avait laissée : vérifier ne doit rien changer.
	var suivant := _chapitre_suivant()
	if suivant != "":
		_noter(suivant)
		print("PAUSE avance rendue : %s" % suivant)

	get_tree().quit()


## Les quatre orientations, sur un même personnage.
##
## Le parcours de campagne aborde toujours par le sud : il prouve que le
## personnage se tourne, jamais qu'il se tourne du bon côté. On éprouve donc la
## géométrie séparément, en déplaçant Wellan autour de lui.
func _eprouver_les_orientations() -> void:
	var cible := ""
	for id in _habitants:
		cible = str(id)
		break
	if cible == "":
		print("ORIENTATION : plus personne dans la salle")
		return

	var corps: Node2D = _habitants[cible]
	for essai in [
		{ "ou": Vector2(0, TUILE), "attendu": "sud" },
		{ "ou": Vector2(0, -TUILE), "attendu": "nord" },
		{ "ou": Vector2(TUILE, 0), "attendu": "est" },
		{ "ou": Vector2(-TUILE, 0), "attendu": "ouest" },
	]:
		_wellan.global_position = corps.global_position + essai["ou"]
		_tourner_vers_moi(cible)
		var rang := -1
		for enfant in corps.get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				rang = int((enfant.texture as AtlasTexture).region.position.y / SPRITE)
		var obtenu := "?"
		for sens in RANGEE:
			if RANGEE[sens] == rang:
				obtenu = sens
		print("ORIENTATION %s %s attendu, %s obtenu" % [
			"OK" if obtenu == essai["attendu"] else "FAUX", essai["attendu"], obtenu])


## Regarde les effets, image par image.
##
## On les prend pendant qu'ils jouent, non après : une animation captée à sa
## fin ne montre que le vide qu'elle laisse. C'est la même faute que la boîte de
## dialogue photographiée une fois fermée.
func _capturer_les_effets() -> void:
	_ouverture.visible = false

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

	# La mort, puis le relèvement. C'est ce qu'on voit qui doit dire qu'il est
	# mort, donc c'est ce qu'il faut regarder.
	_wellan.vie = 0
	_perdre()
	await _attendre(40)
	get_viewport().get_texture().get_image().save_png("res://capture-mort.png")
	print("MORT sprite tourné de %.0f°, mare %s" % [
		_vue.rotation_degrees, "visible" if _mare != null and _mare.visible else "absente"])

	_touche("ui_accept")
	await _attendre(8)
	get_viewport().get_texture().get_image().save_png("res://capture-releve.png")
	print("RELEVE sprite à %.0f°, mare %s, vie %d" % [
		_vue.rotation_degrees, "visible" if _mare != null and _mare.visible else "effacée", _wellan.vie])

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
	# On laisse d'abord arriver ceux qui marchent : les aborder en chemin
	# reviendrait à courir après quelqu'un qui traverse la salle.
	var attente := 0
	var marchait := false
	while attente < 300 and _marcheurs.any(func(m): return m["corps"] == _habitants.get(id)):
		if not marchait:
			marchait = true
			print("MARCHE %s entre depuis %s" % [id, _habitants[id].position / float(TUILE)])
		# Une image en pleine traversée : c'est le mouvement qu'il faut voir,
		# et il a disparu quand la conversation s'ouvre.
		if attente == 24:
			get_viewport().get_texture().get_image().save_png("res://capture-marche-%s.png" % id)
		await get_tree().process_frame
		attente += 1
	if marchait:
		print("ARRIVE %s en %d images, à %s" % [id, attente, _habitants[id].position / float(TUILE)])

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

	# Une image quand plusieurs bulles sont à l'écran : c'est là qu'on voit à
	# quoi elles servent — la quête des six Chevaliers.
	if _bulles.size() >= 3 and not _bulles_capture:
		_bulles_capture = true
		await _attendre(3)
		get_viewport().get_texture().get_image().save_png("res://capture-bulles.png")
		print("BULLES %d à l'écran" % _bulles.size())

	# Une image avant d'ouvrir : c'est le seul moment où l'invite se voit, et
	# elle est là pour être vue.
	if not _invite_capture:
		_invite_capture = true
		# Deux images d'attente : l'invite s'allume dans la passe de physique, et
		# le tampon dessiné a un tour de retard. Capturer aussitôt rendait un
		# écran où elle n'était pas encore peinte, et l'on aurait conclu qu'elle
		# ne s'affichait pas.
		await _attendre(3)
		get_viewport().get_texture().get_image().save_png("res://capture-invite.png")

	var pages := 0
	while pages < 12:
		_touche("ui_accept")
		await _attendre(2)
		pages += 1
		if pages == 2 and _ouverte:
			get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom_image)
		# Et une image dès qu'une description paraît : c'est l'autre affichage,
		# et rien ne prouverait autrement qu'il s'ouvre.
		if _bandeau.visible and not _recit_capture:
			_recit_capture = true
			get_viewport().get_texture().get_image().save_png("res://capture-description.png")
		if not _ouverte and pages > 1:
			break

	# Le personnage s'est-il tourné ? La rangée de sa planche le dit.
	var tourne := "?"
	if _habitants.has(id):
		for enfant in _habitants[id].get_children():
			if enfant is Sprite2D and enfant.texture is AtlasTexture:
				var rang := int((enfant.texture as AtlasTexture).region.position.y / SPRITE)
				for sens in RANGEE:
					if RANGEE[sens] == rang:
						tourne = sens
	print("PARLE %s en %d pages, regarde vers %s" % [id, pages, tourne])


func _garder(nom: String, images: int) -> void:
	await _attendre(images)
	get_viewport().get_texture().get_image().save_png("res://capture-%s.png" % nom)
