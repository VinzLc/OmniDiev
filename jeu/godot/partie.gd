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


## Où se note la partie.
##
## Un test ne joue pas la partie du joueur, mais il doit tout de même éprouver
## l'enchaînement des chapitres — sinon on ne vérifie plus ce qu'on livre. Il
## tient donc son propre carnet.
static func carnet() -> String:
	var a := OS.get_cmdline_user_args()
	if OS.get_cmdline_args().has("--capture") or a.has("--capture") \
		or a.has("--capture-titre") or a.has("--effets"):
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
static func noter(chapitre: String) -> void:
	var c := charger()
	var n := int(c.get("courante", 0))
	var parties: Array = c["parties"]
	if n >= 0 and n < parties.size():
		parties[n] = { "chapitre": chapitre }
	enregistrer(c)


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
