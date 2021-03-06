## test pour normaliser les adresses

##.###################################################################################33
## I. Chargement des données et Mise en forme ====
##.#################################################################################33

# 1- chargement des packages et données ========================

pkgs <-  c("dplyr","stringr", "lubridate", "ggplot2", "sf", "microbenchmark")
inst <- lapply(pkgs, library, character.only = TRUE)


# toutes les adresses sans les 48 vides
allsujet_SansNA.dat <- readRDS("data/allsujet_cleanNA.rds")
geocodage_evs.shp <- sf::st_read("data/geocodev2.geojson", stringsAsFactors = FALSE) %>% 
                        sf::st_transform(2154)

geocodage_clb.shp <- sf::st_read("data/sortie_15_04.shp" , stringsAsFactors = FALSE)

#correction formatage
geocodage_clb.shp$date_start <- parse_date_time(geocodage_clb.shp$date_start, orders = c("my", "dmy"))
geocodage_clb.shp$date_end_a <- parse_date_time(geocodage_clb.shp$date_end_a, orders = c("my", "dmy"))

# 2- un seul fichier avec un point = une ligne

# pas mal d'info et un benchmark ici : https://github.com/r-spatial/sf/issues/669

# test_compar <- microbenchmark(times = 10,  
#                          r1 <- st_difference(geocodage_evs.shp),
#                         r2 <- distinct(geocodage_evs.shp, .keep_all = TRUE),
#                         r3 <- st_intersection(st_transform(geocodage_evs.shp, 2154)),
#                         r4 <- geocodage_evs.shp[!duplicated(geocodage_evs.shp[,"geometry"]),]
#                             )   

# j'ai pris distinct pour piper un peu meme si il est un tout petit plus lents
# je trouve pas que intersection et difference font sens sur des points

# il faut aussi filtrer les cas où il n'y qu'une adresse et manquante
sujet.dat <- allsujet_SansNA.dat %>% 
    dplyr::mutate(sujet = substr(allsujet_SansNA.dat$Id_cart, 1,7)) %>% 
    dplyr::select(sujet, Date_birth) %>% 
    dplyr::group_by(sujet) %>% 
    dplyr::summarize(Date_birth = first(Date_birth))

# un exemple de preparation de données à partir du geocoadage EVS
# table_adresse_test <- geocodage_evs.shp %>% 
#                            dplyr::mutate(sujet_id = substr(geocodage_evs.shp$Id_cart, 1,7),
#                                     adresse_clb = as.numeric(str_extract(geocodage_evs.shp$Id_cart, pattern = "[0-9]{1,2}?$"))) %>% 
#                             dplyr::select(sujet_id, adresse_clb, result_type, source_loc, geometry) %>% 
#                             dplyr::distinct(.keep_all = TRUE) %>% 
#                             dplyr::mutate(adresse_id = row_number()) %>% 
#                             # me faut reorder et mettre dans le bon CRS 
#                             dplyr::select(adresse_id, sujet_id, adresse_clb, result_type,source_loc, geometry) %>% 
#                             sf::st_transform(2154) %>% 
#                             # ici on filtre les sujet sans residences
#                             dplyr::filter(sujet_id %in% sujet.dat$sujet)

# length(unique(table_adresse_test$sujet_id))

# option 1 dans un csv
# write.table(table_adresse_test, 
#             "data/adresse.csv", 
#             sep = ";",
#             quote = FALSE,
#             row.names = FALSE,
#             col.names=FALSE) 

# option 2 via un shapefile  

# st_write(table_adresse_test, dsn = "data/adresse.shp")


##.###################################################################################33
## I. Chargement des données corrigées ====
##.#################################################################################33

## une partie de données a été corrigées à la main et une autre est issue du géocodage
# nous avons decidé de prendre celui d'ESRI comme base
# il faut regrouper les données et normaliser les adresses
# via leur localisation ex :
# On peut avoir une localisation sur un lieu dit imprecis mais il nous faut cependant la 
# meme adresse


## 1. lecture des deux fichiers geocodées à la main + celui que j'avais fait avant ===============

source("Prétraitement_ETL/geocoderalmain.R")

## 2. hors du geocodage main ===================

summary(geocodage_clb.shp)

geocodage_clb_tot.shp <- geocodage_clb.shp %>% 
                            tidyr::unite("info_sup", lieudit_p, compl_add_, pt_remarq_, na.rm = TRUE) %>%
                            dplyr::select(adresse_id = ID_CARTO,
                                date_start = date_start,
                                date_end = date_end_a,
                                commune = Commune,
                                adresse = Adresse,
                                cp = CP,
                                info_sup,
                                Loc_name) %>% 
                            dplyr::mutate(sujet_id = substr(adresse_id, 1,7),
                                        precision = substr(Loc_name, 1, 1), 
                                        source_codage = "ESRI") %>% 
                            dplyr::select(-Loc_name)

geocodage_clb_tot.shp$precision <- as.numeric(geocodage_clb_tot.shp$precision)

summary(geocodage_clb_tot.shp)

rm(geocodage_clb.shp)

## moins ce qui a été fait à la main 

geocodage_clb_auto.shp <- geocodage_clb_tot.shp[!geocodage_clb_tot.shp$adresse_id %in% geocode_main_totale.shp$adresse_id,] 

rm(geocodage_clb_tot.shp)

# si on enleve les cas avec une seule adresse manquante et ceux qui n'ont pas de date départ
# il y a des #value etrange avec des mauvais geocodages
# sf::st_write(test[test$commune == "#VALUE!",], dsn = "data/value.geojson")

arrondissement.shp <-  sf::st_read("data/value.geojson")

arrondissement.shp$precision <- as.numeric(arrondissement.shp$precision)

geocodage_clb_auto.shp <- geocodage_clb_auto.shp[geocodage_clb_auto.shp$sujet_id %in% sujet.dat$sujet,] %>% 
        dplyr::filter(!is.na(date_start)) 

summary(geocodage_clb_auto.shp)

# on doit donc rajouter ces 23 à la mains
geocodage_clb_auto.shp <- geocodage_clb_auto.shp[!geocodage_clb_auto.shp $adresse_id %in% arrondissement.shp$adresse_id,] %>% 
                        bind_rows(arrondissement.shp)

## 3. Tous ensemble ========

geocodage_adresse.shp <- bind_rows(geocodage_clb_auto.shp, geocode_main_totale.shp)

rm(geocodage_clb_auto.shp, geocode_main_totale.shp, arrondissement.shp)

##.###################################################################################33
## II. Normalisation des adresses ====
##.#################################################################################33

## 1. Correction de certains points ========
## pour le calcul du distance on va enlever les territoires d'outre mer et des NA etranges
# il y a des NA à corriger dans les dates .....
geocodage_adresse.shp <- subset(geocodage_adresse.shp, !is.na(geocodage_adresse.shp$precision) & precision < 100)
summary(geocodage_adresse.shp)

## 2. Cluster des adresses  =========================================
# on est en lambert 93 donc la distance est en m 

## 2.1 Avec une matrice de distance/cluster =======
# avantage permet de savoir qu'elles sont les adresses dans le meme cluster
mat_dist <- st_distance(geocodage_adresse.shp)
hc <- hclust(as.dist(mat_dist), method="complete")

# sur d m
d=1

geocodage_adresse.shp$cluster <- cutree(hc, h=d)
# sur une plus grande distance : 50 m cf plot plus bas
geocodage_adresse.shp$bigcluster <- cutree(hc, h=100)
## 2.2 Avec un buffer de d distance et un intersects
# peut être utile de faire un filtre 

buffer_10 <-st_buffer(geocodage_adresse.shp, d)
buffer_50 <- st_buffer(geocodage_adresse.shp, 100) # buffer de 100 m et pas bufer_50 mauvais nom

geocodage_adresse.shp$nb_cluster <-lengths(st_intersects(geocodage_adresse.shp, buffer_10))
geocodage_adresse.shp$nb_bigcluster <-lengths(st_intersects(geocodage_adresse.shp, buffer_50))

rm(hc, buffer_10, buffer_50, mat_dist)

##  2.2 Plot pour regarder l'evolution du clustering en fonction de la distance  ========================

# une fonction de ce qui est fait avec le buffer
number_cluster <- function(data = geocodage_adresse.shp, d) {
                            buffer_XX <- st_buffer(geocodage_adresse.shp, d)
                            dt <- data.frame(d,
                                       sum(lengths(st_intersects(geocodage_adresse.shp, buffer_XX)) != 1))
                            colnames(dt) <- c("d", "nb")
                            return(dt)
}

cluster_dist <- rbind(
    number_cluster(d = 1),
    number_cluster(d = 5),
    number_cluster(d = 10),
    number_cluster(d = 25),
    number_cluster(d = 50),
    number_cluster(d = 100),
    number_cluster(d = 150),
    number_cluster(d = 200)
#    number_cluster(d = 500),
#    number_cluster(d = 1000),
#    number_cluster(d = 10000)
    
)

# graphique du nombre de cluster  

plot(cluster_dist ,
    type = "b",
    ylab = "Nb de clusters avec plus d'une adresse",
    xlab = "distance (m)")

rm(d)

# il y a clusters dont les adresses sont proches au m près on peut les considérer comme des doublons quasi sûr 
# cela correspond soit à des adresses identiques précises soit à des adresses peu precise, ie meme ville
# on peut donc regarder celle qui se regroupe à 50 m près moins celle au m près pour avoir une liste de "probable"

# View(geocodage_adresse.shp[geocodage_adresse.shp$nb_bigcluster > 1 & geocodage_adresse.shp$nb_cluster > 1,] %>% 
#                        dplyr::arrange(bigcluster))

# on a un peu de tout : des adresses différentes mais proches, comme des numeros de rues, 
# des adresses proches avec des niveaux de précision différents exemple,  un numero de rue (1) + la rue en question
# des rues proches mais pas identiques 
# on arrive à regrouper en partie le cas des écoles, lycées, casernes en partie geocodés à la main mais c'est pas tip top
# je pense rajouter "info_sup" dans geocodage adresse au moins pour verifier, puis pe le retirer
# j'ai exporté sur Qgis avec 1 m et 100 m puis j'ai selectionner les clusters bon et pas bon (à la main) 
# le résultats est cluster16_08.geojson

cluster.shp <- st_read("data/cluster16_08.geojson")
# str(cluster.shp)

# un peu de nettoyage on garde le cluster le plus large 
# on eneleve le cluster si idem == 0 ie n'est pas un cluster et du coup prend la valeur de 0
cluster.shp <- cluster.shp  %>% 
    mutate(bigcluster = ifelse(idem == 1, bigcluster, 0) ) %>% 
    select(-c("cluster", "nb_cluster", "idem")) %>% 
    filter(bigcluster != 0) # on retire les non cluster

# hist(cluster.shp$nb_bigcluster)

# il faut changer la loc des points formant le clusters par le point au milieu 
# comment definit-on le milieu ? 
# cas avec deux points et cas avec plus de deux points 

centre_cluster <- cluster.shp %>% 
    filter(nb_bigcluster >= 2) %>% 
    group_by(bigcluster) %>% 
    distinct(count = n_distinct(geometry) ) %>% # on produit un comptage de geometry distinct 
    st_drop_geometry() %>% 
    right_join(cluster.shp, by = "bigcluster") %>% 
    ungroup() %>% 
    st_as_sf(sf_column_name = "geometry")

 
# attention ici meme si on a plusieurs points ils peuvent :
# - se superposer donc on ne peut calculer le polygones
# - n'avoir que deux points differents : lignes

# attention ne marche que pour un cas
centre_cluster$geometry[centre_cluster$count == 3] <- st_centroid(st_combine(st_as_sf(centre_cluster[centre_cluster$count == 3,])) , "POLYGON")
 
# centroid marche pour une ligne, vu notre cas il sera sur la ligne mais utiliser une variante si ligne courbe
centre_cluster_ligne <- aggregate(
    centre_cluster$geometry[centre_cluster$count == 2],
        list(centre_cluster$bigcluster[centre_cluster$count == 2]),
        function(x){st_centroid(st_cast(st_combine(x),"LINESTRING"))} 
        )

# match est utilise pour produire un vecteur d'indexation attribuant on va attribuer le point
centre_cluster$geometry[centre_cluster$count == 2] <- st_sfc(centre_cluster_ligne$geometry)[match(centre_cluster$bigcluster[centre_cluster$count == 2],  centre_cluster_ligne$Group.1)]

# on prepare pour un rajout
transit <- data.frame(
    sort(unique(centre_cluster$bigcluster)),
    1:length(unique(centre_cluster$bigcluster))
)
names(transit) <- c("bigcluster", "addresse_passage")

centre_cluster <- centre_cluster %>% left_join(transit,  by = c("bigcluster" = "bigcluster"))
centre_cluster <-rename(centre_cluster, adresse_clb = adresse_id)

# un bout de la futur table de passage
transit_passage <- centre_cluster %>% 
                        st_drop_geometry() %>% 
                        dplyr::select(addresse_passage, adresse_clb)  #%>%
                        #dplyr::mutate(adresse_id = 1:length(addresse_passage))

names(transit_passage) <- c("adresse_id", "adresse_passage")

length(unique(geocodage_adresse.shp$adresse_id))

centre_cluster_clean <- centre_cluster %>% 
        group_by(addresse_id) %>% 
        summarize(adresse_clb = first(adresse_id),
                  sujet_id = first(sujet_id),
                  precision = first(precision),
                  source_codage = first(source_codage)) 

# il faut retirer les clusters et preparer le jeux de données
# c'est un peu lourd en computation pour ce que cela fait ...
# il y a l'ajout puis la mise en forme
table_adresse.shp <- geocodage_adresse.shp[!geocodage_adresse.shp$adresse_id %in% centre_cluster$adresse_id,] %>% 
    select(-c(date_start, date_end, commune, adresse, cp, info_sup,  nb_cluster, nb_bigcluster)) %>% 
    bind_rows(centre_cluster_clean) %>% 
    group_by(adresse_id) %>% # c'est pas ultra propre
    summarize(sujet_id = first(sujet_id),
              precision = first(precision),
              source_codage = first(source_codage)) %>% 
    dplyr::mutate(adresse_clb = adresse_id) %>% 
    dplyr::mutate(adresse_id = 1:length(adresse_id))  %>% 
    dplyr::select(adresse_id, sujet_id, adresse_clb, precision, source_codage)

# il y a des id de sujet avec  des fautes de frappes à corriger
# oui j'ai verifier 08_006X
table_adresse.shp$sujet_id[table_adresse.shp$sujet_id == "08_006_"] <- "08_0006"
geocodage_adresse.shp$sujet_id[geocodage_adresse.shp$sujet_id == "08_006_"] <- "08_0006"

# st_write(table_adresse.shp,
#          "data/adresse.shp"
#         )
# 3 interval de temps ======================================================


# 3.1 correction des NA  ================================================
# on va avoir un pb avec les NA
summary(geocodage_adresse.shp)

geocodage_adresse.shp[is.na(geocodage_adresse.shp$date_start),]
geocodage_adresse.shp[is.na(geocodage_adresse.shp$date_end),]

# on va les corriger à la main mais c'est automatisable 
# on attribue la date de depart à la date de fin precedente
# c'est potable comme hypothese mais pas fou si c'est une adresse temporaire
# pb geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "08_0006_2"] ou je vois pas trop quoi faire à part dropper
# dans le cas ou c'est la dernière residence on attribue le max de date_end
# geocodage_adresse.shp[geocodage_adresse.shp$sujet_id  %in% geocodage_adresse.shp$sujet_id[is.na(geocodage_adresse.shp$date_end)],] %>% View()

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "01_1095_1"] <- geocodage_adresse.shp$date_start[geocodage_adresse.shp$adresse_id == "01_1095_2"]
geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "01_1095_3"] <- geocodage_adresse.shp$date_start[geocodage_adresse.shp$adresse_id == "01_1095_4"]

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "02_0961_13"] <- max(geocodage_adresse.shp$date_end, na.rm = T)

# ici pas de seconde adresse j'ai pris la troisème
geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "05_0901_1"] <- geocodage_adresse.shp$date_start[geocodage_adresse.shp$adresse_id == "05_0901_3"] 

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "09_1255_4"] <- max(geocodage_adresse.shp$date_end, na.rm = T)

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "16_0757_3"] <- max(geocodage_adresse.shp$date_end, na.rm = T)

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "16_0784_3"] <- max(geocodage_adresse.shp$date_end, na.rm = T)

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "20_1221_5"] <- max(geocodage_adresse.shp$date_end, na.rm = T)

geocodage_adresse.shp$date_end[geocodage_adresse.shp$adresse_id == "22_1055_4"] <- max(geocodage_adresse.shp$date_end, na.rm = T)


# 3.2 table intermediaire de passage ==================================================

table_adresse <- table_adresse.shp %>% 
    st_drop_geometry() %>% 
    select(adresse_id, adresse_clb)

buffer_adresse <- st_buffer(table_adresse.shp, 1) %>% 
    select(adresse_id)

geocodage_adresse_temporelle <- st_intersection(buffer_adresse, geocodage_adresse.shp) %>% 
                                    st_drop_geometry() %>% 
                                    select(adresse_id, adresse_clb = adresse_id.1, date_start, date_end) %>% 
                                    filter(!is.na(date_start)) %>% # ici je vire le NA de 08_0006
                                    filter(!is.na(date_end)) %>%  # ici 12_0748_1
                                    arrange(adresse_id)

# une verif
lapply(list(table_adresse, geocodage_adresse_temporelle), dim)


# 3.3 table interval ==================================================================

geocodage_adresse_temporelle$inter <- paste(geocodage_adresse_temporelle$date_start, geocodage_adresse_temporelle$date_end)

# il y a des intervals vides .....

interval_temp <- geocodage_adresse_temporelle %>% 
    filter(!is.na(date_start)) %>% 
    group_by(inter) %>% 
    summarize(count = n()) %>% 
    mutate(interval_id = 1:length(inter)) 

table_interval_date <- left_join(geocodage_adresse_temporelle,  interval_temp, by = "inter") %>% 
    select(interval_id, adresse_id, date_start, date_end)

# table de passage
p_table_adresse_interval <- table_interval_date %>% 
    select(adresse_id, interval_id) %>% 
    arrange(desc(interval_id))

write.table(p_table_adresse_interval,
            "data/p_table_adresse_interval.csv",
            sep = ",",
            quote = FALSE,
            row.names = FALSE,
            col.names=FALSE)

#table d'interval 
table_interval_date <- left_join(geocodage_adresse_temporelle,  interval_temp, by = "inter") %>% 
    select(interval_id, date_start, date_end) %>% 
    group_by(interval_id) %>% 
    summarize(date_start = first(date_start),
              date_end = first(date_end))

write.table(table_interval_date,
            "data/table_interval_date.csv",
            sep = ",",
            quote = FALSE,
            row.names = FALSE,
            col.names=FALSE)