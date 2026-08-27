extends RefCounted
##
## Lire un fichier de données du jeu.
##
## Trois scripts en avaient chacun leur copie, à la virgule près. Une lecture
## JSON qui rend un dictionnaire vide plutôt que de planter n'a aucune raison
## d'exister trois fois.

## Le contenu d'un fichier JSON, ou un dictionnaire vide s'il manque ou s'il est
## illisible. Un fichier de données absent n'est pas une erreur fatale : la
## scène qui l'appelle sait décider quoi faire d'un vide, pas d'une exception.
static func lire(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		return {}
	var contenu = JSON.parse_string(FileAccess.get_file_as_string(chemin))
	return contenu if contenu is Dictionary else {}
