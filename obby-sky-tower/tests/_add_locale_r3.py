# One-off helper (round 3): adds the strings of the 1,000-stage update to the 12 locale files.
# Kept in the repo as a record of the batch; tests/locale_test.luau is what guards the result.
import re, io, sys

KEYS = """progress.sub progress.sub_done tower.1 tower.2 tower.3 tower.4 tower.5 tower.6 tower.7 tower.8 tower.9 tower.10
gift.at gift.got gift.1.name gift.2.name gift.3.name gift.4.name gift.5.name gift.6.name gift.7.name gift.8.name gift.9.name gift.10.name
power.speed.name power.gravity.name power.doublejump.name power.shield.name power.magnet.name power.skip.name power.pocket.name
shop.zone prompt.buy prompt.take prompt.enter prompt.portal prompt.lobby
perk.teleport.name perk.glider.name perk.cloud.name perk.dash.name perk.triplejump.name perk.glow_gold.name perk.glow_cyan.name perk.glow_pink.name perk.glow_green.name perk.glow_rainbow.name perk.jumpfx_ring.name perk.jumpfx_stars.name perk.lounge_neon.name perk.lounge_sunrise.name perk.lounge_stars.name
lounge.sign lounge.free portal.next portal.home sign.tower_clear board.stage title.conqueror title.legend
err.portal_locked err.pocket_here err.no_charges err.boost_full err.max_charges err.lounge_locked err.need_gift err.travel_locked
msg.pocket_placed msg.roam_on msg.roam_off msg.perk_on msg.perk_off
hud.portal hud.dash hud.pocket hud.explore_off celebrate.tower celebrate.tower_enter panel.travel travel.lobby travel.world win.portal
store.DoubleJump.name store.DoubleJump.desc store.InfiniteRevives.name store.InfiniteRevives.desc
run.unranked win.info intro.tagline""".split()

T = {}
T["en"] = """Tower {n}: {name}  ·  🎁 {stage}: {gift}
Tower {n}: {name}
Sky Tower
Sunset Tower
Midnight Tower
Storm Tower
Crystal Tower
Inferno Tower
Frozen Tower
Toxic Tower
Void Tower
Rainbow Tower
STAGE {n} GIFT
New gift: {name}!
Summit Flame trail
Cloud Buddy pet
Lucky Charm: x1.5 coins
Aurora aura
Title: Halfway Legend
A free skip every day
Rainbow glow skin
Comet trail
Diamond Charm: x2 coins
Sky Crown
Speed Coil (3 min)
Gravity Coil (3 min)
Double Jump (5 min)
Shield (1 hit)
Coin Magnet (5 min)
Skip Stage
Pocket Checkpoint
POWER-UP SHOP
Buy
Take
Enter
Portal
Lobby
Teleporter
Glider
Flying Cloud
Dash
Triple Jump
Gold Glow
Cyan Glow
Pink Glow
Green Glow
Rainbow Glow
Jump Ring
Jump Stars
Neon trail
Sunrise trail
Starlight aura
WINNER'S LOUNGE - ALL FREE
FREE
TOWER {n}: {name}\\nStages {from}-{to}
BACK TO THE LOBBY
TOWER {n} CLEARED!\\n{name}
HIGHEST STAGE
Conqueror of 1000
Halfway Legend
Reach stage {n} to open this portal
You can't place a checkpoint here
None left - buy more at a shop
That power-up is already at its maximum
You can't carry any more of those
Reach stage 100 to use the Winner's Lounge
That is the gift of stage {n}
You haven't reached that world yet
Pocket checkpoint placed!
Explore mode: checkpoints don't count until you stop
Explore mode off - back to your checkpoint
{name}: ON
{name}: OFF
ENTER PORTAL
Dash
Save here
Stop exploring
TOWER {n} CLEARED!
TOWER {n}
Teleporter
Lobby
World {n}\\nStage {stage}
Enter the portal: stages 101-1000
Double Jump
One extra jump in the air, for ever
Infinite Revives
Unlimited pocket checkpoints
Assisted - not ranked
You beat the first tower! Take the portal to stages 101-1000, or rebirth to race the first 100 again.
Climb 1,000 stages across 10 towers!"""

T["es"] = """Torre {n}: {name}  ·  🎁 {stage}: {gift}
Torre {n}: {name}
Torre del Cielo
Torre del Atardecer
Torre de Medianoche
Torre de la Tormenta
Torre de Cristal
Torre Infernal
Torre Helada
Torre Tóxica
Torre del Vacío
Torre Arcoíris
REGALO DEL NIVEL {n}
¡Regalo nuevo: {name}!
Estela Llama de la Cima
Mascota Nubecita
Amuleto de la suerte: x1,5 monedas
Aura Aurora
Título: Leyenda a Medio Camino
Un salto gratis cada día
Skin de brillo arcoíris
Estela Cometa
Amuleto de diamante: x2 monedas
Corona del Cielo
Bobina de velocidad (3 min)
Bobina de gravedad (3 min)
Doble salto (5 min)
Escudo (1 golpe)
Imán de monedas (5 min)
Saltar nivel
Checkpoint portátil
TIENDA DE VENTAJAS
Comprar
Tomar
Entrar
Portal
Lobby
Teletransporte
Planeador
Nube voladora
Impulso
Triple salto
Brillo dorado
Brillo cian
Brillo rosa
Brillo verde
Brillo arcoíris
Anillo de salto
Estrellas de salto
Estela Neón
Estela Amanecer
Aura Luz de estrellas
SALA DEL GANADOR - TODO GRATIS
GRATIS
TORRE {n}: {name}\\nNiveles {from}-{to}
VOLVER AL LOBBY
¡TORRE {n} SUPERADA!\\n{name}
NIVEL MÁS ALTO
Conquistador de los 1000
Leyenda a Medio Camino
Llega al nivel {n} para abrir este portal
Aquí no puedes poner un checkpoint
No te quedan: compra más en una tienda
Esa ventaja ya está al máximo
No puedes llevar más de esos
Llega al nivel 100 para usar la Sala del Ganador
Ese es el regalo del nivel {n}
Todavía no llegaste a ese mundo
¡Checkpoint portátil colocado!
Modo exploración: los checkpoints no cuentan hasta que lo apagues
Modo exploración apagado: vuelves a tu checkpoint
{name}: SÍ
{name}: NO
ENTRAR AL PORTAL
Impulso
Guardar aquí
Dejar de explorar
¡TORRE {n} SUPERADA!
TORRE {n}
Teletransporte
Lobby
Mundo {n}\\nNivel {stage}
Entrar al portal: niveles 101-1000
Doble salto
Un salto extra en el aire, para siempre
Revivir infinito
Checkpoints portátiles sin límite
Con ayuda - sin ranking
¡Superaste la primera torre! Toma el portal a los niveles 101-1000, o renace para correr de nuevo los primeros 100.
¡Sube 1000 niveles en 10 torres!"""

T["pt"] = """Torre {n}: {name}  ·  🎁 {stage}: {gift}
Torre {n}: {name}
Torre do Céu
Torre do Pôr do Sol
Torre da Meia-Noite
Torre da Tempestade
Torre de Cristal
Torre Infernal
Torre Congelada
Torre Tóxica
Torre do Vazio
Torre Arco-Íris
PRESENTE DA FASE {n}
Presente novo: {name}!
Rastro Chama do Topo
Pet Nuvenzinha
Amuleto da sorte: x1,5 moedas
Aura Aurora
Título: Lenda do Meio do Caminho
Um pulo grátis todo dia
Skin de brilho arco-íris
Rastro Cometa
Amuleto de diamante: x2 moedas
Coroa do Céu
Bobina de velocidade (3 min)
Bobina de gravidade (3 min)
Pulo duplo (5 min)
Escudo (1 golpe)
Ímã de moedas (5 min)
Pular fase
Checkpoint de bolso
LOJA DE VANTAGENS
Comprar
Pegar
Entrar
Portal
Lobby
Teletransporte
Planador
Nuvem voadora
Arrancada
Pulo triplo
Brilho dourado
Brilho ciano
Brilho rosa
Brilho verde
Brilho arco-íris
Anel de pulo
Estrelas de pulo
Rastro Neon
Rastro Amanhecer
Aura Luz das estrelas
SALA DO VENCEDOR - TUDO GRÁTIS
GRÁTIS
TORRE {n}: {name}\\nFases {from}-{to}
VOLTAR AO LOBBY
TORRE {n} CONCLUÍDA!\\n{name}
FASE MAIS ALTA
Conquistador das 1000
Lenda do Meio do Caminho
Chegue à fase {n} para abrir este portal
Você não pode colocar um checkpoint aqui
Acabou: compre mais em uma loja
Essa vantagem já está no máximo
Você não pode carregar mais desses
Chegue à fase 100 para usar a Sala do Vencedor
Esse é o presente da fase {n}
Você ainda não chegou a esse mundo
Checkpoint de bolso colocado!
Modo exploração: os checkpoints não contam até você parar
Modo exploração desligado: de volta ao seu checkpoint
{name}: LIGADO
{name}: DESLIGADO
ENTRAR NO PORTAL
Arrancada
Salvar aqui
Parar de explorar
TORRE {n} CONCLUÍDA!
TORRE {n}
Teletransporte
Lobby
Mundo {n}\\nFase {stage}
Entrar no portal: fases 101-1000
Pulo duplo
Um pulo extra no ar, para sempre
Reviver infinito
Checkpoints de bolso sem limite
Com ajuda - sem ranking
Você venceu a primeira torre! Pegue o portal para as fases 101-1000, ou renasça para correr as 100 primeiras de novo.
Suba 1000 fases em 10 torres!"""

T["fr"] = """Tour {n} : {name}  ·  🎁 {stage} : {gift}
Tour {n} : {name}
Tour du Ciel
Tour du Crépuscule
Tour de Minuit
Tour de l'Orage
Tour de Cristal
Tour Infernale
Tour Gelée
Tour Toxique
Tour du Néant
Tour Arc-en-ciel
CADEAU DE L'ÉTAPE {n}
Nouveau cadeau : {name} !
Traînée Flamme du Sommet
Familier Petit Nuage
Porte-bonheur : pièces x1,5
Aura Aurore
Titre : Légende à mi-chemin
Un saut gratuit chaque jour
Skin lueur arc-en-ciel
Traînée Comète
Charme de diamant : pièces x2
Couronne du Ciel
Bobine de vitesse (3 min)
Bobine de gravité (3 min)
Double saut (5 min)
Bouclier (1 coup)
Aimant à pièces (5 min)
Passer l'étape
Checkpoint de poche
BOUTIQUE DE BONUS
Acheter
Prendre
Entrer
Portail
Lobby
Téléporteur
Planeur
Nuage volant
Ruée
Triple saut
Lueur dorée
Lueur cyan
Lueur rose
Lueur verte
Lueur arc-en-ciel
Anneau de saut
Étoiles de saut
Traînée Néon
Traînée Aube
Aura Lumière d'étoiles
SALON DU VAINQUEUR - TOUT EST GRATUIT
GRATUIT
TOUR {n} : {name}\\nÉtapes {from}-{to}
RETOUR AU LOBBY
TOUR {n} TERMINÉE !\\n{name}
ÉTAPE LA PLUS HAUTE
Conquérant des 1000
Légende à mi-chemin
Atteins l'étape {n} pour ouvrir ce portail
Tu ne peux pas poser de checkpoint ici
Il n'y en a plus : achètes-en dans une boutique
Ce bonus est déjà au maximum
Tu ne peux pas en porter plus
Atteins l'étape 100 pour utiliser le Salon du Vainqueur
C'est le cadeau de l'étape {n}
Tu n'as pas encore atteint ce monde
Checkpoint de poche posé !
Mode exploration : les checkpoints ne comptent pas tant que tu n'arrêtes pas
Mode exploration arrêté : retour à ton checkpoint
{name} : OUI
{name} : NON
ENTRER DANS LE PORTAIL
Ruée
Sauver ici
Arrêter d'explorer
TOUR {n} TERMINÉE !
TOUR {n}
Téléporteur
Lobby
Monde {n}\\nÉtape {stage}
Entrer dans le portail : étapes 101-1000
Double saut
Un saut de plus en l'air, pour toujours
Réanimations infinies
Checkpoints de poche illimités
Avec aide - non classé
Tu as vaincu la première tour ! Prends le portail vers les étapes 101-1000, ou renais pour refaire la course des 100 premières.
Grimpe 1000 étapes sur 10 tours !"""

T["de"] = """Turm {n}: {name}  ·  🎁 {stage}: {gift}
Turm {n}: {name}
Himmelsturm
Abendturm
Mitternachtsturm
Sturmturm
Kristallturm
Infernoturm
Eisturm
Giftturm
Turm der Leere
Regenbogenturm
GESCHENK VON LEVEL {n}
Neues Geschenk: {name}!
Spur Gipfelflamme
Begleiter Wölkchen
Glücksbringer: x1,5 Münzen
Aura Polarlicht
Titel: Legende der Halbzeit
Jeden Tag ein Gratis-Skip
Regenbogen-Leuchtskin
Spur Komet
Diamant-Glücksbringer: x2 Münzen
Himmelskrone
Tempo-Spule (3 Min)
Schwerkraft-Spule (3 Min)
Doppelsprung (5 Min)
Schild (1 Treffer)
Münzmagnet (5 Min)
Level überspringen
Taschen-Checkpoint
POWER-UP-LADEN
Kaufen
Nehmen
Betreten
Portal
Lobby
Teleporter
Gleiter
Fliegende Wolke
Sprint
Dreifachsprung
Goldleuchten
Cyanleuchten
Pinkleuchten
Grünleuchten
Regenbogenleuchten
Sprungring
Sprungsterne
Spur Neon
Spur Sonnenaufgang
Aura Sternenlicht
SIEGER-LOUNGE - ALLES GRATIS
GRATIS
TURM {n}: {name}\\nLevel {from}-{to}
ZURÜCK ZUR LOBBY
TURM {n} GESCHAFFT!\\n{name}
HÖCHSTES LEVEL
Bezwinger der 1000
Legende der Halbzeit
Erreiche Level {n}, um dieses Portal zu öffnen
Hier kannst du keinen Checkpoint setzen
Keine mehr übrig: kauf welche im Laden
Dieses Power-up ist schon am Maximum
Mehr davon kannst du nicht tragen
Erreiche Level 100 für die Sieger-Lounge
Das ist das Geschenk von Level {n}
Diese Welt hast du noch nicht erreicht
Taschen-Checkpoint gesetzt!
Erkundungsmodus: Checkpoints zählen nicht, bis du aufhörst
Erkundungsmodus aus: zurück zu deinem Checkpoint
{name}: AN
{name}: AUS
PORTAL BETRETEN
Sprint
Hier sichern
Erkunden beenden
TURM {n} GESCHAFFT!
TURM {n}
Teleporter
Lobby
Welt {n}\\nLevel {stage}
Portal betreten: Level 101-1000
Doppelsprung
Ein zusätzlicher Sprung in der Luft, für immer
Unendlich Wiederbeleben
Unbegrenzte Taschen-Checkpoints
Mit Hilfe - ohne Rangliste
Du hast den ersten Turm geschafft! Nimm das Portal zu Level 101-1000 oder starte neu und renne die ersten 100 noch einmal.
Klettere 1000 Level in 10 Türmen!"""

T["id"] = """Menara {n}: {name}  ·  🎁 {stage}: {gift}
Menara {n}: {name}
Menara Langit
Menara Senja
Menara Tengah Malam
Menara Badai
Menara Kristal
Menara Inferno
Menara Beku
Menara Beracun
Menara Hampa
Menara Pelangi
HADIAH STAGE {n}
Hadiah baru: {name}!
Jejak Api Puncak
Peliharaan Si Awan
Jimat Keberuntungan: koin x1,5
Aura Aurora
Gelar: Legenda Separuh Jalan
Satu skip gratis setiap hari
Skin cahaya pelangi
Jejak Komet
Jimat Berlian: koin x2
Mahkota Langit
Koil Kecepatan (3 mnt)
Koil Gravitasi (3 mnt)
Lompat Ganda (5 mnt)
Perisai (1 kena)
Magnet Koin (5 mnt)
Lewati Stage
Checkpoint Saku
TOKO POWER-UP
Beli
Ambil
Masuk
Portal
Lobby
Teleporter
Glider
Awan Terbang
Dash
Lompat Tiga Kali
Cahaya Emas
Cahaya Sian
Cahaya Pink
Cahaya Hijau
Cahaya Pelangi
Cincin Lompat
Bintang Lompat
Jejak Neon
Jejak Matahari Terbit
Aura Cahaya Bintang
RUANG PEMENANG - SEMUA GRATIS
GRATIS
MENARA {n}: {name}\\nStage {from}-{to}
KEMBALI KE LOBBY
MENARA {n} SELESAI!\\n{name}
STAGE TERTINGGI
Penakluk 1000
Legenda Separuh Jalan
Capai stage {n} untuk membuka portal ini
Kamu tidak bisa menaruh checkpoint di sini
Habis: beli lagi di toko
Power-up itu sudah maksimal
Kamu tidak bisa membawa lebih banyak
Capai stage 100 untuk memakai Ruang Pemenang
Itu hadiah stage {n}
Kamu belum sampai ke dunia itu
Checkpoint saku dipasang!
Mode jelajah: checkpoint tidak dihitung sampai kamu berhenti
Mode jelajah mati: kembali ke checkpoint-mu
{name}: NYALA
{name}: MATI
MASUK PORTAL
Dash
Simpan di sini
Berhenti jelajah
MENARA {n} SELESAI!
MENARA {n}
Teleporter
Lobby
Dunia {n}\\nStage {stage}
Masuk portal: stage 101-1000
Lompat Ganda
Satu lompatan ekstra di udara, selamanya
Hidup Lagi Tanpa Batas
Checkpoint saku tanpa batas
Dibantu - tanpa peringkat
Kamu menaklukkan menara pertama! Masuk portal ke stage 101-1000, atau rebirth untuk balapan 100 stage pertama lagi.
Panjat 1000 stage di 10 menara!"""

T["tr"] = """Kule {n}: {name}  ·  🎁 {stage}: {gift}
Kule {n}: {name}
Gök Kulesi
Gün Batımı Kulesi
Gece Yarısı Kulesi
Fırtına Kulesi
Kristal Kule
Cehennem Kulesi
Buz Kulesi
Zehirli Kule
Boşluk Kulesi
Gökkuşağı Kulesi
{n}. BÖLÜM HEDİYESİ
Yeni hediye: {name}!
Zirve Alevi izi
Bulut Dostu evcil hayvanı
Şans Tılsımı: x1,5 para
Aurora aurası
Unvan: Yarı Yol Efsanesi
Her gün bir bedava geçiş
Gökkuşağı parıltı kostümü
Kuyruklu Yıldız izi
Elmas Tılsım: x2 para
Gök Tacı
Hız Bobini (3 dk)
Yerçekimi Bobini (3 dk)
Çift Zıplama (5 dk)
Kalkan (1 darbe)
Para Mıknatısı (5 dk)
Bölümü Geç
Cep Kontrol Noktası
GÜÇLENDİRME DÜKKANI
Satın al
Al
Gir
Portal
Lobi
Işınlayıcı
Planör
Uçan Bulut
Atılma
Üçlü Zıplama
Altın Parıltı
Camgöbeği Parıltı
Pembe Parıltı
Yeşil Parıltı
Gökkuşağı Parıltı
Zıplama Halkası
Zıplama Yıldızları
Neon izi
Gün Doğumu izi
Yıldız Işığı aurası
KAZANANLAR SALONU - HEPSİ BEDAVA
BEDAVA
KULE {n}: {name}\\nBölüm {from}-{to}
LOBİYE DÖN
KULE {n} TAMAMLANDI!\\n{name}
EN YÜKSEK BÖLÜM
1000'in Fatihi
Yarı Yol Efsanesi
Bu portalı açmak için {n}. bölüme ulaş
Buraya kontrol noktası koyamazsın
Kalmadı: dükkandan daha fazla al
Bu güçlendirme zaten en üst seviyede
Bunlardan daha fazla taşıyamazsın
Kazananlar Salonu için 100. bölüme ulaş
Bu, {n}. bölümün hediyesi
O dünyaya henüz ulaşmadın
Cep kontrol noktası kondu!
Keşif modu: durana kadar kontrol noktaları sayılmaz
Keşif modu kapalı: kontrol noktana döndün
{name}: AÇIK
{name}: KAPALI
PORTALA GİR
Atılma
Buraya kaydet
Keşfi bırak
KULE {n} TAMAMLANDI!
KULE {n}
Işınlayıcı
Lobi
Dünya {n}\\nBölüm {stage}
Portala gir: bölüm 101-1000
Çift Zıplama
Havada bir zıplama daha, sonsuza dek
Sonsuz Canlanma
Sınırsız cep kontrol noktası
Yardımlı - sıralama yok
İlk kuleyi bitirdin! Portaldan 101-1000. bölümlere geç ya da yeniden doğup ilk 100'ü tekrar yarış.
10 kulede 1000 bölüm tırman!"""

T["ru"] = """Башня {n}: {name}  ·  🎁 {stage}: {gift}
Башня {n}: {name}
Небесная башня
Башня заката
Башня полуночи
Башня бури
Хрустальная башня
Башня пламени
Ледяная башня
Ядовитая башня
Башня пустоты
Радужная башня
ПОДАРОК ЭТАПА {n}
Новый подарок: {name}!
След «Пламя вершины»
Питомец Облачко
Талисман удачи: монеты x1,5
Аура «Сияние»
Титул: Легенда полпути
Бесплатный пропуск каждый день
Радужное свечение
След «Комета»
Алмазный талисман: монеты x2
Небесная корона
Катушка скорости (3 мин)
Катушка гравитации (3 мин)
Двойной прыжок (5 мин)
Щит (1 удар)
Магнит монет (5 мин)
Пропустить этап
Карманный чекпоинт
МАГАЗИН УСИЛЕНИЙ
Купить
Взять
Войти
Портал
Лобби
Телепорт
Планёр
Летающее облако
Рывок
Тройной прыжок
Золотое свечение
Голубое свечение
Розовое свечение
Зелёное свечение
Радужное свечение
Кольцо прыжка
Звёзды прыжка
След «Неон»
След «Рассвет»
Аура «Звёздный свет»
ЗАЛ ПОБЕДИТЕЛЯ - ВСЁ БЕСПЛАТНО
БЕСПЛАТНО
БАШНЯ {n}: {name}\\nЭтапы {from}-{to}
НАЗАД В ЛОББИ
БАШНЯ {n} ПРОЙДЕНА!\\n{name}
ЛУЧШИЙ ЭТАП
Покоритель 1000
Легенда полпути
Дойди до этапа {n}, чтобы открыть портал
Здесь нельзя поставить чекпоинт
Закончились: купи ещё в магазине
Это усиление уже на максимуме
Больше таких взять нельзя
Дойди до этапа 100, чтобы попасть в Зал победителя
Это подарок этапа {n}
Ты ещё не дошёл до этого мира
Карманный чекпоинт поставлен!
Режим полёта: чекпоинты не засчитываются, пока не выключишь
Режим полёта выключен: возврат к чекпоинту
{name}: ВКЛ
{name}: ВЫКЛ
ВОЙТИ В ПОРТАЛ
Рывок
Сохранить тут
Закончить полёт
БАШНЯ {n} ПРОЙДЕНА!
БАШНЯ {n}
Телепорт
Лобби
Мир {n}\\nЭтап {stage}
Войти в портал: этапы 101-1000
Двойной прыжок
Ещё один прыжок в воздухе, навсегда
Бесконечное возрождение
Карманные чекпоинты без ограничений
С помощью - вне рейтинга
Первая башня пройдена! Войди в портал к этапам 101-1000 или переродись и пробеги первые 100 заново.
Пройди 1000 этапов в 10 башнях!"""

T["ja"] = """タワー{n}: {name}  ·  🎁 {stage}: {gift}
タワー{n}: {name}
スカイタワー
夕焼けタワー
真夜中タワー
嵐のタワー
クリスタルタワー
インフェルノタワー
氷のタワー
どくどくタワー
虚空タワー
レインボータワー
ステージ{n}のギフト
新しいギフト: {name}!
トレイル「頂上の炎」
ペット「くもちゃん」
ラッキーチャーム: コイン1.5倍
オーロラのオーラ
称号: 折り返しのレジェンド
毎日スキップ1回無料
レインボーグロースキン
トレイル「彗星」
ダイヤのチャーム: コイン2倍
スカイクラウン
スピードコイル(3分)
グラビティコイル(3分)
2段ジャンプ(5分)
シールド(1回)
コインマグネット(5分)
ステージスキップ
ポケットチェックポイント
パワーアップショップ
買う
もらう
入る
ポータル
ロビー
テレポーター
グライダー
空飛ぶ雲
ダッシュ
3段ジャンプ
ゴールドグロー
シアングロー
ピンクグロー
グリーングロー
レインボーグロー
ジャンプリング
ジャンプスター
トレイル「ネオン」
トレイル「日の出」
オーラ「星明かり」
勝者のラウンジ - ぜんぶ無料
無料
タワー{n}: {name}\\nステージ {from}-{to}
ロビーにもどる
タワー{n} クリア!\\n{name}
最高ステージ
1000の覇者
折り返しのレジェンド
ステージ{n}に着くとこのポータルが開くよ
ここにはチェックポイントを置けないよ
もうないよ: ショップで買ってね
そのパワーアップはもう最大だよ
これ以上は持てないよ
ステージ100に着くと勝者のラウンジが使えるよ
それはステージ{n}のギフトだよ
そのワールドにはまだ着いていないよ
ポケットチェックポイントを置いたよ!
探検モード: やめるまでチェックポイントはカウントされないよ
探検モード終了: チェックポイントにもどったよ
{name}: オン
{name}: オフ
ポータルに入る
ダッシュ
ここでセーブ
探検をやめる
タワー{n} クリア!
タワー{n}
テレポーター
ロビー
ワールド{n}\\nステージ{stage}
ポータルに入る: ステージ101-1000
2段ジャンプ
空中でもう1回ジャンプ、ずっと使える
無限リバイブ
ポケットチェックポイント使い放題
アシストあり - ランク外
最初のタワーをクリア! ポータルでステージ101-1000へ進むか、リバースして最初の100をもう一度走ろう。
10のタワーで1000ステージをのぼろう!"""

T["ko"] = """타워 {n}: {name}  ·  🎁 {stage}: {gift}
타워 {n}: {name}
스카이 타워
노을 타워
한밤의 타워
폭풍 타워
크리스탈 타워
인페르노 타워
얼음 타워
독 타워
공허의 타워
무지개 타워
스테이지 {n} 선물
새 선물: {name}!
정상의 불꽃 트레일
구름 친구 펫
행운의 부적: 코인 1.5배
오로라 오라
칭호: 반환점의 전설
매일 무료 스킵 1회
무지개 빛 스킨
혜성 트레일
다이아 부적: 코인 2배
하늘 왕관
스피드 코일 (3분)
중력 코일 (3분)
2단 점프 (5분)
방패 (1회)
코인 자석 (5분)
스테이지 스킵
포켓 체크포인트
파워업 상점
구매
받기
들어가기
포털
로비
텔레포터
글라이더
나는 구름
대시
3단 점프
골드 글로우
시안 글로우
핑크 글로우
그린 글로우
무지개 글로우
점프 링
점프 스타
네온 트레일
해돋이 트레일
별빛 오라
우승자 라운지 - 전부 무료
무료
타워 {n}: {name}\\n스테이지 {from}-{to}
로비로 돌아가기
타워 {n} 클리어!\\n{name}
최고 스테이지
1000의 정복자
반환점의 전설
스테이지 {n}에 도달하면 이 포털이 열려요
여기에는 체크포인트를 놓을 수 없어요
남은 게 없어요: 상점에서 더 사세요
그 파워업은 이미 최대예요
더 이상 가질 수 없어요
스테이지 100에 도달하면 우승자 라운지를 쓸 수 있어요
그건 스테이지 {n}의 선물이에요
아직 그 월드에 도달하지 못했어요
포켓 체크포인트를 놓았어요!
탐험 모드: 멈출 때까지 체크포인트가 기록되지 않아요
탐험 모드 종료: 체크포인트로 돌아왔어요
{name}: 켜짐
{name}: 꺼짐
포털 들어가기
대시
여기 저장
탐험 끝내기
타워 {n} 클리어!
타워 {n}
텔레포터
로비
월드 {n}\\n스테이지 {stage}
포털 들어가기: 스테이지 101-1000
2단 점프
공중에서 한 번 더 점프, 영구
무한 부활
포켓 체크포인트 무제한
도움 사용 - 랭킹 제외
첫 번째 타워를 깼어요! 포털로 스테이지 101-1000에 가거나, 환생해서 처음 100개를 다시 달려 보세요.
타워 10개, 스테이지 1000개를 올라가요!"""

T["th"] = """หอคอย {n}: {name}  ·  🎁 {stage}: {gift}
หอคอย {n}: {name}
หอคอยท้องฟ้า
หอคอยอาทิตย์อัสดง
หอคอยเที่ยงคืน
หอคอยพายุ
หอคอยคริสตัล
หอคอยเพลิง
หอคอยน้ำแข็ง
หอคอยพิษ
หอคอยความว่างเปล่า
หอคอยสายรุ้ง
ของขวัญด่าน {n}
ของขวัญใหม่: {name}!
เทรลเปลวไฟยอดหอคอย
สัตว์เลี้ยงเจ้าก้อนเมฆ
เครื่องรางนำโชค: เหรียญ x1.5
ออร่าแสงเหนือ
ฉายา: ตำนานครึ่งทาง
ข้ามฟรีทุกวัน
สกินเรืองแสงสายรุ้ง
เทรลดาวหาง
เครื่องรางเพชร: เหรียญ x2
มงกุฎท้องฟ้า
คอยล์ความเร็ว (3 นาที)
คอยล์แรงโน้มถ่วง (3 นาที)
กระโดดสองชั้น (5 นาที)
โล่ (1 ครั้ง)
แม่เหล็กเหรียญ (5 นาที)
ข้ามด่าน
เช็กพอยต์พกพา
ร้านพาวเวอร์อัป
ซื้อ
รับ
เข้า
พอร์ทัล
ล็อบบี้
เครื่องเทเลพอร์ต
เครื่องร่อน
เมฆบิน
พุ่งตัว
กระโดดสามชั้น
แสงสีทอง
แสงสีฟ้า
แสงสีชมพู
แสงสีเขียว
แสงสายรุ้ง
วงแหวนกระโดด
ดาวกระโดด
เทรลนีออน
เทรลอรุณรุ่ง
ออร่าแสงดาว
ห้องผู้ชนะ - ฟรีทั้งหมด
ฟรี
หอคอย {n}: {name}\\nด่าน {from}-{to}
กลับล็อบบี้
ผ่านหอคอย {n} แล้ว!\\n{name}
ด่านสูงสุด
ผู้พิชิต 1000
ตำนานครึ่งทาง
ไปให้ถึงด่าน {n} เพื่อเปิดพอร์ทัลนี้
วางเช็กพอยต์ตรงนี้ไม่ได้
หมดแล้ว: ซื้อเพิ่มที่ร้าน
พาวเวอร์อัปนั้นเต็มแล้ว
ถือเพิ่มไม่ได้แล้ว
ไปให้ถึงด่าน 100 เพื่อใช้ห้องผู้ชนะ
นั่นคือของขวัญของด่าน {n}
คุณยังไปไม่ถึงโลกนั้น
วางเช็กพอยต์พกพาแล้ว!
โหมดสำรวจ: เช็กพอยต์จะไม่นับจนกว่าจะหยุด
ปิดโหมดสำรวจ: กลับไปที่เช็กพอยต์ของคุณ
{name}: เปิด
{name}: ปิด
เข้าพอร์ทัล
พุ่งตัว
เซฟตรงนี้
หยุดสำรวจ
ผ่านหอคอย {n} แล้ว!
หอคอย {n}
เครื่องเทเลพอร์ต
ล็อบบี้
โลก {n}\\nด่าน {stage}
เข้าพอร์ทัล: ด่าน 101-1000
กระโดดสองชั้น
กระโดดกลางอากาศได้อีกครั้ง ตลอดไป
ฟื้นไม่จำกัด
เช็กพอยต์พกพาไม่จำกัด
มีตัวช่วย - ไม่ติดอันดับ
คุณผ่านหอคอยแรกแล้ว! เข้าพอร์ทัลไปด่าน 101-1000 หรือเกิดใหม่เพื่อแข่ง 100 ด่านแรกอีกครั้ง
ปีน 1000 ด่านใน 10 หอคอย!"""

T["vi"] = """Tháp {n}: {name}  ·  🎁 {stage}: {gift}
Tháp {n}: {name}
Tháp Bầu Trời
Tháp Hoàng Hôn
Tháp Nửa Đêm
Tháp Bão Tố
Tháp Pha Lê
Tháp Hỏa Ngục
Tháp Băng Giá
Tháp Độc
Tháp Hư Không
Tháp Cầu Vồng
QUÀ MÀN {n}
Quà mới: {name}!
Vệt Lửa Đỉnh Tháp
Thú cưng Mây Nhỏ
Bùa may mắn: xu x1,5
Hào quang Cực Quang
Danh hiệu: Huyền thoại nửa đường
Mỗi ngày một lượt bỏ qua miễn phí
Skin phát sáng cầu vồng
Vệt Sao Chổi
Bùa kim cương: xu x2
Vương miện Bầu Trời
Cuộn tốc độ (3 phút)
Cuộn trọng lực (3 phút)
Nhảy đôi (5 phút)
Khiên (1 lần)
Nam châm xu (5 phút)
Bỏ qua màn
Điểm lưu bỏ túi
CỬA HÀNG TRỢ LỰC
Mua
Nhận
Vào
Cổng
Sảnh
Máy dịch chuyển
Tàu lượn
Mây bay
Lướt
Nhảy ba
Ánh vàng
Ánh xanh lơ
Ánh hồng
Ánh xanh lá
Ánh cầu vồng
Vòng nhảy
Sao nhảy
Vệt Neon
Vệt Bình Minh
Hào quang Ánh Sao
PHÒNG NHÀ VÔ ĐỊCH - MIỄN PHÍ HẾT
MIỄN PHÍ
THÁP {n}: {name}\\nMàn {from}-{to}
VỀ SẢNH
ĐÃ QUA THÁP {n}!\\n{name}
MÀN CAO NHẤT
Người chinh phục 1000
Huyền thoại nửa đường
Tới màn {n} để mở cổng này
Không thể đặt điểm lưu ở đây
Hết rồi: mua thêm ở cửa hàng
Trợ lực đó đã tối đa
Bạn không mang thêm được nữa
Tới màn 100 để dùng Phòng Nhà Vô Địch
Đó là quà của màn {n}
Bạn chưa tới thế giới đó
Đã đặt điểm lưu bỏ túi!
Chế độ khám phá: điểm lưu không tính cho tới khi bạn dừng
Tắt chế độ khám phá: về điểm lưu của bạn
{name}: BẬT
{name}: TẮT
VÀO CỔNG
Lướt
Lưu ở đây
Dừng khám phá
ĐÃ QUA THÁP {n}!
THÁP {n}
Máy dịch chuyển
Sảnh
Thế giới {n}\\nMàn {stage}
Vào cổng: màn 101-1000
Nhảy đôi
Thêm một lần nhảy trên không, mãi mãi
Hồi sinh vô hạn
Điểm lưu bỏ túi không giới hạn
Có trợ giúp - không xếp hạng
Bạn đã qua tháp đầu tiên! Vào cổng tới màn 101-1000, hoặc tái sinh để đua lại 100 màn đầu.
Leo 1000 màn qua 10 tòa tháp!"""

ok = True
for code, text in T.items():
    lines = text.split("\n")
    if len(lines) != len(KEYS):
        print("COUNT MISMATCH", code, len(lines), len(KEYS)); ok = False
if not ok:
    sys.exit(1)

for code, text in T.items():
    lines = text.split("\n")
    p = f"src/shared/Locales/{code}.luau"
    s = open(p, encoding="utf-8").read()
    add = []
    for key, val in zip(KEYS, lines):
        val = val.replace('"', '\\"')
        pat = re.compile(r'\t\["' + re.escape(key) + r'"\] = "(?:[^"\\]|\\.)*",\n')
        entry = f'\t["{key}"] = "{val}",\n'
        if pat.search(s):
            s = pat.sub(lambda m: entry, s, count=1)
        else:
            add.append(entry)
    i = s.rstrip().rfind("}")
    s = s[:i] + "\n\t-- 1,000 stages: towers, gifts, shops, lounge (round 3)\n" + "".join(add) + "}\n"
    open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok", len(KEYS))
