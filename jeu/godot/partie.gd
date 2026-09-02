extends RefCounted
##
## La partie du joueur : où elle est notée, où elle en est.
##
## L'écran-titre et le jeu en avaient chacun leur version, avec la même règle du
## carnet d'essai recopiée dans les deux. Une divergence entre les deux copies
## aurait écrit dans la sauvegarde du joueur pendant un test — ce qui est
## exactement l'accident qu'on cherche à ne plus reproduire.

const Donnees := preload("res://donnees.gd")

const FICHIER := "user://parties.json"
const FICHIER_ESSAI := "user://parties-essai.json"
const EMPLACEMENTS := 3
const CAMPAGNE := "res://donnees/campagne.json"

## Le chapitre qu'on a demandé à rejouer, le temps d'un rechargement de scène.
##
## Statique plutôt qu'écrit dans le carnet : c'est une intention qui ne survit
## pas à la session, et l'inscrire dans la sauvegarde du joueur y laisserait la
## trace de quelque chose qui n'est pas sa progression. Le script reste chargé
## d'une scène à l'autre, la valeur aussi.
static var rejoue := ""


## Où se note la partie.
##
## Un test ne joue pas la partie du joueur, mais il doit tout de même éprouver
## l'enchaînement des chapitres — sinon on ne vérifie plus ce qu'on livre. Il
## tient donc son propre carnet.
static func carnet() -> String:
	var a := OS.get_cmdline_user_args()
	if OS.get_cmdline_args().has("--capture") or a.has("--capture") \
		or a.has("--capture-titre") or a.has("--effets") or a.has("--verifier"):
		return FICHIER_ESSAI
	return FICHIER


## Le carnet entier, normalisé : un emplacement courant et trois cases.
static func charger() -> Dictionary:
	var c := Donnees.lire(carnet())
	if not c.has("parties"):
		return { "courante": 0, "parties": [null, null, null] }
	return c


static func enregistrer(c: Dictionary) -> void:
	var f := FileAccess.open(carnet(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(c))


## L'emplacement en cours, vide s'il n'a jamais été ouvert.
static func courante() -> Dictionary:
	var c := charger()
	var parties: Array = c["parties"]
	var n := int(c.get("courante", 0))
	if n < 0 or n >= parties.size() or parties[n] == null:
		return {}
	return parties[n]


## Note où l'on en est dans l'emplacement courant.
##
## Complète l'emplacement au lieu de le remplacer. Il ne portait que le
## chapitre, et y écrire un dictionnaire neuf suffisait ; le Codex y range
## maintenant les rencontres, qu'une note de chapitre aurait effacées sans un
## mot. Une écriture ne rend jamais moins que ce qu'elle a trouvé.
static func noter(chapitre: String) -> void:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n >= 0 and n < parties.size():
		var partie := _emplacement(parties, n)
		partie["chapitre"] = chapitre
		# Le plus loin qu'on soit allé, qui ne redescend jamais.
		#
		# Sans lui, rejouer le premier chapitre effacerait toute l'avance : la
		# sauvegarde ne porte que « où j'en suis », et « où j'en suis » vaudrait
		# soudain « chapitre un ». C'est la même règle que partout ailleurs —
		# une écriture ne rend jamais moins que ce qu'elle a trouvé.
		if rang(chapitre) > rang(str(partie.get("atteint", ""))):
			partie["atteint"] = chapitre
		parties[n] = partie
	enregistrer(c)


## Retient un fait dans l'emplacement courant, sans rien effacer d'autre.
##
## Même règle que `noter` : on complète, on ne remplace pas. C'est par là que le
## jeu se souvient d'avoir déjà montré l'écran des commandes.
static func retenir(cle: String, valeur) -> void:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n < 0 or n >= parties.size():
		return
	var partie := _emplacement(parties, n)
	partie[cle] = valeur
	parties[n] = partie
	enregistrer(c)


static func retenu(cle: String, defaut = null):
	return courante().get(cle, defaut)


## L'emplacement n, créé vide s'il n'existe pas encore.
static func _emplacement(parties: Array, n: int) -> Dictionary:
	return parties[n] if parties[n] is Dictionary else {}


## Inscrit un personnage au Codex. Vrai si c'est la première fois.
##
## Écrit sur-le-champ plutôt qu'à la sauvegarde : une collection ne se perd pas
## parce qu'on a quitté sans noter. C'est aussi pourquoi elle échappe à la règle
## qui empêche une scène jouée à la main de compter — inscrire quelqu'un ajoute,
## et ne déplace jamais la campagne.
static func rencontrer(id: String) -> bool:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n < 0 or n >= parties.size():
		return false
	var partie := _emplacement(parties, n)
	var vus: Array = partie.get("rencontres", [])
	if vus.has(id):
		return false
	vus.append(id)
	partie["rencontres"] = vus
	parties[n] = partie
	enregistrer(c)
	return true


## Ramasse un objet. Vrai si c'est la première fois.
##
## Même forme que `rencontrer`, et pour la même raison : c'est ce qui permet de
## n'annoncer une prise qu'une fois, et d'écrire sur-le-champ plutôt qu'à la
## sauvegarde. Un coffre ouvert doit rester ouvert même si l'on quitte sans
## noter.
static func prendre(id: String) -> bool:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n < 0 or n >= parties.size():
		return false
	var partie := _emplacement(parties, n)
	var sac: Array = partie.get("sac", [])
	if sac.has(id):
		return false
	sac.append(id)
	partie["sac"] = sac
	parties[n] = partie
	enregistrer(c)
	return true


## Ce qu'on porte, dans l'ordre où on l'a ramassé.
static func sac() -> Array:
	return courante().get("sac", [])


## Porte un équipement à son emplacement. Rend ce qui s'y trouvait.
##
## Un emplacement ne tient qu'une pièce : porter une seconde épée repose la
## première dans le sac plutôt que de l'y ajouter deux fois. Passer une chaîne
## vide déséquipe.
static func equiper(emplacement: String, id: String) -> String:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n < 0 or n >= parties.size():
		return ""
	var partie := _emplacement(parties, n)
	var porte: Dictionary = partie.get("equipe", {})
	var avant := str(porte.get(emplacement, ""))
	if id == "":
		porte.erase(emplacement)
	else:
		porte[emplacement] = id
	partie["equipe"] = porte
	parties[n] = partie
	enregistrer(c)
	return avant


## Ce qu'on porte, par emplacement.
static func equipe() -> Dictionary:
	return courante().get("equipe", {})


## Tous ceux à qui l'on a parlé, dans l'ordre où on les a rencontrés.
static func rencontres() -> Array:
	return courante().get("rencontres", [])


## Le chapitre le plus avancé qu'on ait ouvert.
##
## Les anciennes sauvegardes ne le portent pas : on retombe alors sur le
## chapitre courant, qui était la seule marque d'avance qui existât.
static func atteint() -> String:
	var c := courante()
	return str(c.get("atteint", c.get("chapitre", "")))


## Les chapitres qu'on a le droit de rejouer : tous ceux déjà ouverts.
static func joues() -> Array:
	var loin := rang(atteint())
	var liste := []
	for id in campagne():
		if rang(str(id)) <= loin:
			liste.append(str(id))
	return liste


## L'ordre de lecture des chapitres.
static func campagne() -> Array:
	return Donnees.lire(CAMPAGNE).get("chapitres", [])


## Le chapitre suivant, vide s'il n'y en a plus.
static func suivant(chapitre: String) -> String:
	var suite := campagne()
	var i := suite.find(chapitre)
	return str(suite[i + 1]) if i >= 0 and i + 1 < suite.size() else ""


## Le rang d'un chapitre dans la campagne, zéro s'il n'y figure pas.
static func rang(chapitre: String) -> int:
	return campagne().find(chapitre) + 1


## Le titre d'un chapitre, lu dans sa scène.
static func titre(chapitre: String) -> String:
	return str(Donnees.lire("res://donnees/scenes/%s.json" % chapitre).get("titre", chapitre))
