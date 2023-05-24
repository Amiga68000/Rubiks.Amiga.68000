;--- DEBUG

DEBUGDISPLAY_TIME=1	;COUT=2 HBL	;affiche le compteur de rater
DEBUGDISPLAY_RASTER=0	;affiche la couleur raster rouge/vert
CTR=1					;count waitblit and put value in CTRWAIT:

;Programme Arnaud.68000 - 2020-11
;contact : amiga68000 at gmail dot com
;Rotation RUBIK'S filaire 3D
;
;assembleur : ASMTwo
;
;References :
;Reprise architecture (init hardware, copperlist, ombre et miroir) :
;source : Yragael pour Stash of Code (http://www.stashofcode.fr) en 2017.
;
;contient le fichier Font8 :
;https://www.stashofcode.fr/code/coder-un-sine-scroll-sur-amiga/sinescroll.zip
;
;Textes paragraphes 
;https://www.topster.fr/texte-ascii/ivrit.html
;

;--- Gestion de CONF ---
;Arnaud.68000
;2020-11-23 	- Afficher en couleur filaire
;2020-11-24 	- Nettoyage Code pour plus de lisibilité
;2020-11-25 	- Calcul des points dans table reduite (évite redondance test normale Y)
;				- Remplacement de code (44 -> 16 cycles ): Rotation de plan : lsr.l #7,d4 & lsr.l #7,d4 -->  Swap d4,	rol.l #2,d4
;2020-11-27a	- GAIN 10 VPOS : Calcul de la NORMALE basee que sur l'axe Y, ajout sub Calculer_Y_Axes_Ax_AZ() 
;2020-11-27b	- GAIN 50 VPOS : Calcul des normales des axes 6 axes (Calcul / 9) + chaque polygone s'y refere(quand la pièce n'est pas dans une couronne en rotation).
;				- AllocMem en 1 fois et en Chip
;				- Clarifier le code avec des SUB
;2020-11-28a	- GAIN 20 VPOS - Calcul Calculer_XZ_3Axes() sans Y car inutile pour un affichage ISO-Métrique
;2020-11-29		- GAIN 40 VPOS - cos(a) et sin(a) chargés dans Dn et accès pas Swap Dn
;				  au lieu d'appleler à chaque fois move.w (An,Dn),dm où An=table de sin et dn angle
;				  de plus, libère des registres pour accès via (An)+ dans sur de calcul au lieu de #POLYCALCULE-POLY(An)
;2020-11-30		- GAIN 0 VPOS - CALCULER_LES_POLYGONES_XZ() modifié pour calcul des adresses destination type move d0,OFSSET(A5) --> move d0,(A5)+
;2020-12-01		- GAIN 10 VPOS - POLY_CALCULES devient une table de points à tracer, supprime les tests d'orientation de face
;Actuel : 1 HBL + 208, 158 VPOS (fonction des faces du cube)
;2021-02-02		- créer les rotations de couronne
;				- afficher textes
;2021-02-08		- debug fin rotation 90° => RotCour_TournerCoordsSelonAngle90 au lieu de RotCour_Tourner90EtCopierPOLYSauves 
;2021-02-26		- simplication of the code (Chip allocation and copperlist) adding tricks from Heavy (https://eab.abime.net)
;2023-04-20		- tables cos.w sin.w --> table cos+sin.l
;2023-04-21		- GAIN 10 VPOS - matrice de rotation http://flabrador.free.fr/lexo/m68k/tuto3d/chapitre8.html


;.--- TODO Developpement
;TODO : Debugger les décalages de faces lors des rotations de couronnes
;TODO : afficher en plein
;TODO : gérer les interférences de polygones (lors de rotation couronne)
;TODO : ajouter de la musique
;TODO : faire des animations cube + texte + musique
;TODO : passer en rotation manuelle à la demande

;--- TODO pistes optimisation
;TODO OPTIISATION : table TRIGO SUR 256 donc rotation sur 1 octet = plus besoin de comparer à 360
;TODO OPTIISATION : Gain 10 HBL : ne pas appeler calcul3D mais recopier le code (utiliser les macros)
;TODO OPTIISATION : Faire le RAZ de BitplaneC quand CPU occupe et ne pas attendre le Blitter (50 VBH perdus)
;TODO OPTIISATION ; Faire une rotation sur 2 axes, donc blanquer le 3eme axe
;TODO Basecode portable "utilise un basecode existant, de blueberry, stingray, etc… pour Jel, voir YouTube"
;TODO supprimer les espaces dans les tables
;TODO mettre la copperlist direct en chip dans un section copper,data_c
;TODO idem pour les screens (appelés ici bitplaneA,B,C) dans un section screen,bss_c "le bss ça ne prend aucune place dans le code :  c’est un hunk d’allocmem que le systeme fera automatiquement."
;TODO OPTIMISATION : EVITER RALENTISSEMENT : mixer les couleurs des faces pour éviter d'avoir 3 faces consécutives dont les couleurs sont sur 2 bitplanes 


	SECTION Arnaud.68000,CODE_C

ROT_COURONNE_EN_CONTINU=1
Calculer3D=1		;COUT=160 HBL, 		;calcule les rotations,
AffLigneRUBIKS=1	;COUT=155, 205 HBL 	;affiche le rubiks
AffTexteFixe=1		;COUT=37 HBL environ	;texte fixe
EffacerBitPlaneCache=1	;COUT=43 HBL 		;3eme Bitplane



;Angles au depart
InitAngleAx	equ 30
InitAngleAy	equ 50
InitAngleAz	equ 30
;Incrément des axes
PasAngleAX	equ 1
PasAngleAY	equ 2
PasAngleAZ	equ 0

;position du centre objet. rayon maxi 92 pix  equ  sqr(3*53^2), coins max 53,53,53
RayonMaxi 	equ 96	;doit tre un miltiple de 8 pix, utilisé pour RAZ au blitter
offsetX 	equ 160		;min 87, maxi 232
offsetZ 	equ 100		;mini 87, maxi 168  87=sqr(50^2+50^2+50^2) coin max (50,50,50)


;---- Librairies -----
ExecBase 		equ 4                  ;location of the exec.lib
OldOpenLibrary 	equ -408
OpenLib 		equ -552                ;offset to the openLibrary function
OpenLibVersion 	equ 34           ;minimum version to use
CloseLib 		equ -414               ;offset to closeLibrary function
PutString 		equ -948              ;offset to putStr() function
AllocMem		equ	-198
FreeMem			equ	-210
Forbid 			equ -132
Permit 			equ -138


;---- Registres -----
VPOSR 	equ $004
VHPOSR 	equ $006
INTENA 	equ $09A
INTENAR equ $01C
INTREQ 	equ $09C
INTREQR equ $01E
DMACON 	equ $096
DMACONR equ $002
BLTAFWM equ $044
BLTALWM equ $046
BLTAPTH equ $050
BLTAPTL equ $052
BLTCPTH equ $048
BLTDPTH equ $054
BLTAMOD equ $064
BLTBMOD equ $062
BLTCMOD equ $060
BLTDMOD equ $066
BLTADAT equ $074
BLTBDAT equ $072
BLTCON0 equ $040
BLTCON1 equ $042
BLTSIZE equ $058
DIWSTRT equ $08E
DIWSTOP equ $090
BPLCON0 equ $100
BPLCON1 equ $102
BPLCON2 equ $104
DDFSTRT equ $092
DDFSTOP equ $094
BPL1MOD equ $108
BPL2MOD equ $10A
BPL1PTH equ $0E0
BPL1PTL equ $0E2
BPL2PTH equ $0E4
BPL2PTL equ $0E6
BPL3PTH equ $0E8
BPL3PTL equ $0EA
COLOR00 equ $180
COLOR01 equ $182
COLOR02 equ $184
COLOR03 equ $186
COLOR04 equ $188
COLOR05 equ $18A
COLOR06 equ $18C
COLOR07 equ $18E
COLOR08	equ	$190
COP1LCH equ $080
COPJMP1 equ $088
FMODE 	equ $1FC


;Programme

DISPLAY_DEPTH=3
DISPLAY_DX=320
DISPLAY_DY=256
DISPLAY_X=$81
DISPLAY_Y=$2C
SCROLL_DX=DISPLAY_DX
SCROLL_X=(DISPLAY_DX-SCROLL_DX)>>1
SCROLL_DY=100
SCROLL_AMPLITUDE=SCROLL_DY-16	;SCROLL_DY-16 donne l'amplitude des ordonnées possibles du scroll : [0,SCROLL_DY-16]
								;SCROLL_DY doit être pair pour centrer le scroll sur DISPLAY_DY qui est pair
								;Donc SCROLL_DY-16 est pair
								;Les ordonnées sont calculées par (A>>1)*sin ce qui donne des valeurs dans [-A,A] quand A est pair et dans [-A+1,A+1] quand A est impair
								;Ici A=SCROLL_DY-16 donc A est pair : pas de correction à apporter
SCROLL_Y=(DISPLAY_DY-SCROLL_DY)>>1
;SCROLL_SPEED=2
SCROLL_COLOR=$0FFF
SINE_SPEED_FRAME=5
SINE_SPEED_PIXEL=1
LINE_DX=15	;C'est le nombre de lignes de la droite - 1 : LINE_DX=max (abs(15-0),abs(0,0))
LINE_DY=0	;C'est le nombre de colonnes de la droite - 1 : LINE_DY=min (abs(15-0),abs(0,0))
LINE_OCTANT=1
MIRROR_Y=SCROLL_Y+SCROLL_DY	;Ordonnée de la ligne à laquelle débute le miroir (le WAIT pour modifier BPL1MOD a lieu une ligne avant)
MIRROR_COLOR=$000A
MIRROR_SCROLL_COLOR=$000F
SHADOW_DX=0 ;2	;Compris entre 0 et 15
SHADOW_DY=0 ;2
SHADOW_COLOR=$0777

TAILLE_BITPLANE=((DISPLAY_DX*DISPLAY_DY)>>3)

SCROLL_POS_Y=162
SCROLL_SPEED=1



;  __  __     _      ___   ___    ___  
; |  \/  |   /_\    / __| | _ \  / _ \ 
; | |\/| |  / _ \  | (__  |   / | (_) |
; |_|  |_| /_/ \_\  \___| |_|_\  \___/ 
;
;--- MACROS ---

;--- MACRO Attendre le Blitter. 
;Quand la seconde opérande est une adresse, BTST ne permet de tester que les bits 7-0 de l'octet pointé, 
;mais traitant la première opérande comme le numéro du bit modulo 8, 
;BTST #14,DMACONR(a5) revient à tester le bit 14%8=6 de l'octet de poids fort de DMACONR, 
;ce qui correspond bien à BBUSY...

WAITBLIT:	MACRO
_waitBlitter0\@
	IFNE CTR
	;add.l	#1,CTRWait
	ENDC
	btst #6,DMACONR(a5)
	;bne _waitBlitter0\@
_waitBlitter1\@
	IFNE CTR
	add.l	#1,CTRWait
	ENDC
	btst #6,DMACONR(a5)
	bne _waitBlitter1\@
	IFNE CTR
	sub.l	#1,CTRWait
	ENDC
	ENDM


;AFFTEXTE 0,0,"Hello World" ;MACRO : x,y,"texte"
	
AFFTEXTE: MACRO	;\1=x.car, \2=y.car, \3="Texte" 
	move.l 	bitplaneB(pc),a2
	;add.l	#TAILLE_BITPLANE,a2
	lea		.txt\@(pc),a3
	add.l	#\2*40*8+\1,A2	;y*40*8+x (pas de 8 pix)
	Jsr		AfficherTexte8x8	;d0,A0,A2,A3 utilisés
	bra		.finTxt\@
.txt\@:
	dc.b	\3,0
	even	
.finTxt\@:
	ENDM	
	
	
;calculs en fixed point.
;les valeurs de sinus et cosinus sont codés sur 16 bits 
;avec 2 bits pour la valeur entière et 14 bits pour la valeur décimale, 
;lorsque nous allons multiplier deux données en fixed point 
;nous allons obtenir une valeur 32 bits, 
;il va falloir la convertir en fixed point de 16 bits, 
;c'est le role de la macro suivante :

	
FIXEDVAL16x16  MACRO
	lsl.l	#2,\1
	swap   \1
	ENDM
       
;  ___          _             _   
; |   \   ___  | |__   _  _  | |_ 
; | |) | / -_) | '_ \ | || | |  _|
; |___/  \___| |_.__/  \_,_|  \__|
;                                 
;---------- Initialisations ----------

Debut:



	movem.l d0-d7/a0-a6,-(SP) ;Empiler les registres
	
	lea 	$DFF000,a5
	movea.l	$4.w,a6
	jsr		ReserverMemoireCHIP
	jsr		CouperHardware
	jsr		InitiliserCopperList
	jsr		CreerPolice16x16
	
	
;  _                       
; | |     ___   ___   _ __ 
; | |__  / _ \ / _ \ | '_ \
; |____| \___/ \___/ | .__/
;                    |_|   		
;---------- Boucle principale ----------


_loop:
	
	jsr 	GERER_ROTATION_COURONNE
	lea 	$DFF000,a5
	
	
	IFNE CTR
	move.l	#0,CTRWait
	ENDC
	

;--- Attendre que le faisceau d'électrons a terminé de tracer l'écran
_waitVBL:
	move.l VPOSR(a5),d0
	lsr.l #8,d0
	and.w #$01FF,d0
	cmp.w #DISPLAY_Y+DISPLAY_DY,d0

	
	blt _waitVBL
	
	IFNE DEBUGDISPLAY_RASTER
	move.w #$0F00,COLOR00(a5)	;si DEBUG on passe en rouge la couleur du fond
	ENDC

;----- PERMUTER LES BITPLANE ----------
	;Permuter circulairement les bitplanes : A(à afficher) --> C(à effacer) --> B(à construire) --> A
	
	move.l bitplaneA(pc),d0
	move.l bitplaneB(pc),d1
	move.l bitplaneC(pc),d2
	move.l d1,bitplaneA	;Bitplane Affiché
	move.l d2,bitplaneB	;Bitplane en construction
	move.l d0,bitplaneC ;Bitplane en effacement

;----- AFFICHER BitPlaneA VIA COPPERLIST ----------
	;ecriture des adresses bitplane dans la copperlist
	movea.l	Copperlist_BitPlanes_PTR,a0
	;BitplaneA0
	move.w 	d1,2(a0)
	swap 	d1
	move.w 	d1,6(a0)
	swap 	d1
	add.l	#TAILLE_BITPLANE,d1
	;BitplaneA1
	move.w	d1,10(a0)
	swap 	d1
	move.w	d1,14(a0)
	swap 	d1
	add.l	#TAILLE_BITPLANE,d1
	;BitplaneA2
	move.w	d1,18(a0)
	swap 	d1
	move.w	d1,22(a0)

	
	
	
	
	
	IFNE AffTexteFixe
	
	;jsr		AFFICHER_TEXTES_PREPARES(pc) ;cout 35 HBL
	jsr		AFFICHER_TEXTES	;cout 37 HBL
	

	ENDC



;-- CALCUL 3D ********************************
	
	IFNE Calculer3D
	
Calcul3D:
    
	movem.l d0-d7/a0-a6,-(sp)


;--- CALCULER LES ANGLES ---------

	
	lea		Angles(pc),a2
	;Increment angle aX
	move.w	(a2),d3
	add.w  	#PasAngleAX,d3  ;increment AX
	cmp.w	#360,d3
	blo     PasModuloIncrementAx
    sub.w   #360,d3
PasModuloIncrementAx:
	move.w	d3,(A2)+
	;Increment angle aY
	move.w	(a2),d4
	add.w  	#PasAngleAY,d4  ;increment AY
	cmp.w	#360,d4
	blo     PasModuloIncrementAy
    sub.w   #360,d4
PasModuloIncrementAy:
	move.w	d4,(A2)+
	;Increment angle aZ
	move.w	(a2),d5
	add.w  	#PasAngleAZ,d5  ;increment AZ
	cmp.w	#360,d5
	blo     PasModuloIncrementAz
    sub.w   #360,d5
PasModuloIncrementAz:
	move.w	d5,(A2)		

 ;--- CHARGER LES TABLES TRIGO
	lea		CosSinTbl(pc),a2
	;A4=aX
    lsl.w	#2,d3		;aX*4
    move.l  (a2,d3),d3  ;cos(aX) sin(aX)
	;A5=aY
	lsl.w	#2,d4	
  	move.l  (a2,d4),d4  ;cos(aY) sin(aY)
	;A6=aZ
	lsl.w	#2,d5
	move.l  (a2,d5),d5  ;cos(aZ) sin(aZ)



;--- CALCULER LES POINTS
	;dont les normales sont orientées vers observateur
	;y représente la profondeur, si y> alors face visibel
	;POLY:    		dc.w    -50,0,0, 2, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
	;POLYCALCULES : dc.w 	couleur (1..6), pointA1 (x,y,z), pointA2 (x,y,z), pointB1 (x,y,z), pointB2 (x,y,z)

	jsr		CALCULER_TABLE_DES_NORMALES(pc)


;--- CALCULER LES POINTS DES POLYGONES
	jsr		CalculerMatriceRotation(pc)
	jsr		CALCULER_LES_POLYGONES_XZ(pc)
	
	
	movem.l (sp)+,d0-d7/a0-a6
	  
	ENDC
	
	
	movem.l d0-d7/a0-a6,-(sp)


	IFNE AffLigneRUBIKS
	jsr		TRACER_LIGNES_POLYGONES_XZ(pc)
	ENDC




;--- TRACER LES AXES DE ROTATION
	
	IFNE AffLigneRUBIKS 
		IFNE DEBUGDISPLAY_TIME
			bsr	Tracer_DEBUG_ANGLE(pc)
		ENDC
	ENDC

	movem.l (sp)+,d0-d7/a0-a6




		

;--- EFFACER LE BITPLANE CACHE -------------------
	IFNE EffacerBitPlaneCache
	
			;--- Efface dans Bitplane C
	
		
	;jsr		Effacer_BitPlaneC(pc)
	jsr		Effacer_BitPlaneC0(pc)
	jsr		Effacer_BitPlaneC1(pc)
	jsr		Effacer_BitPlaneC2(pc)
	
	IFNE DEBUGDISPLAY_TIME
	jsr	Effacer_Debug_Angle
	ENDC
	

	
	ENDC
	
	
	
	
	
;--- AFFICHE LE FAISCEAU EN VERT
	IFNE DEBUGDISPLAY_RASTER
	move.w	#$00F0,COLOR00(a5)
	ELSE

	ENDC
	
	
;********** DEBUGDISPLAYTIME (start) **********
	;affiche en décimal le nombre de lignes écoulées depuis la fin de l'écran (depuis la ligne DISPLAY_Y+DISPLAY_DY incluse)
	;la trame se termine en DISPLAY_Y+DISPLAY_DY-1
	;le temps est donc compté en nombre de ligne à partir de DISPLAY_Y+DISPLAY_DY incluse
	IFNE DEBUGDISPLAY_TIME
	movem.l	d0-d2/a0-a3,-(sp)

	move.l	VPOSR(a5),d0
	lsr.l	#8,d0
	and.w	#$01FF,d0
	cmp.w	#DISPLAY_Y+DISPLAY_DY,d0
	bge 	_timeBelowBitplanes
	;on est passé en haut de l'écran
	add.w 	#1+312-(DISPLAY_Y+DISPLAY_DY-1),d0	;312 est la ligne la plus basse que peut trace le faisceau d'électrons
	bra 	_timeDisplayCounter
_timeBelowBitplanes:
	;on est toujours en bas de l'écran
	sub.w	#DISPLAY_Y+DISPLAY_DY-1,d0
 _timeDisplayCounter:
	movea.l	bitplaneB(pc),a1
	lea 	24*(DISPLAY_DX>>3)(a1),a1

	jsr		AFficherNombre	;D0=nombre 9999, A1=ptr 

	movem.l	(sp)+,d0-d2/a0-a3
	ENDC
	
	
	IFNE ROT_COURONNE_EN_CONTINU
	;Execute des rotations indéfiniment
	jsr		RotCour_SEQ_Demarrer_RotationALEATOIRE
	ENDC

;--- SOURIS PRESSEE ?
TestClicDroit;
	btst 	#10,$dff016 ; test RIGHT mouse click
	bne		TestClicGauche
	;-- clic Gauche enfoncé
.loopCG:
	;-- clic Gauche non laché
	btst 	#10,$dff016 ; test RIGHT mouse click
	;beq		.loopCG	
	
	jsr		RotCour_SEQ_Demarrer_RotationALEATOIRE
	bra 	_loop
TestClicGauche:		

	btst	#6,$bfe001
	bne	_loop
	
	
;  ___   _        
; | __| (_)  _ _  
; | _|  | | | ' \ 
; |_|   |_| |_||_|	
;	
;--- ON QUITTE ------------
	
_loopEnd:	
	WAITBLIT
	jsr RestaurerHardware(pc)
	jsr	LibererMemoireCHIP(pc)
ErrorMem:
	movem.l (sp)+,d0-d7/a0-a6	;Dépiler les registres
	rts





AFficherNombre:
	;=>d0.w = #nombre 9999 max à afficher
	and.l	#$0000FFFF,d0	;nombre à afficher
	moveq	#0,d1
	moveq	#3-1,d2	;4 digits
.blcConvert:
		divu	#10,d0		;=> d0=reste:quotient de la division de d0 sur 32 bits
		swap	d0
		add.b	#$30-$20,d0	;code ASCII "0" moins l'offset de début dans font8 ($20)
		move.b	d0,d1
		lsl.l	#8,d1
		clr.w	d0
		swap	d0
	dbf 	d2,.blcConvert
	divu 	#10,d0		;=> d0=reste:quotient de la division de d0 sur 32 bits
	swap 	d0
	add.b	#$30-$20,d0	;code ASCII de "0" moins l'offset de début dans font8 ($20)
	move.b	d0,d1
	;d1 = suite des 4 offsets ASCII dans la police des 4 chiffres à afficher
	;     mais en sens inverse (ex: 123 => "3210")
	lea 	font8(pc),a0
	moveq 	#4-1,d0
.timeLoopDisplay:
		clr.w 	d2
		move.b 	d1,d2
		lsl.w 	#3,d2
		lea 	(a0,d2.w),a2
		move.l 	a1,a3
		moveq	#8-1,d2
	.timeLoopDisplayChar:
			move.b	(a2)+,(a3)
			lea 	DISPLAY_DX>>3(a3),a3
		dbf 	d2,.timeLoopDisplayChar
		lea 	1(a1),a1
		lsr.l	#8,d1
	dbf	d0,.timeLoopDisplay
	rts

	

;  ___   _   _   ___         ___                _     _                   
; / __| | | | | | _ )  ___  | _ \  ___   _  _  | |_  (_)  _ _    ___   ___
; \__ \ | |_| | | _ \ |___| |   / / _ \ | || | |  _| | | | ' \  / -_) (_-<
; |___/  \___/  |___/       |_|_\ \___/  \_,_|  \__| |_| |_||_| \___| /__/
;                                                                         



;--- TIRER DES NOMBRES ALEATOIRES

Aleatoire1A6:	;D0=1..6 ; d0, d1, d2
	jsr		_RandomByte
	;bit 0 (0 ou 1)
	move.b	d0,d1
	and.w	#%0001,d1
	;bit 1 (0 ou 1)
	move.b	d0,d2
	and.w	#%0010,d2
	lsr.w	#1,d2
	add.w	d2,d1
	;bit 2 et 3 (0 à 3)
	and.w	#%1100,d0
	lsr.w	#2,d0
	add.w	d1,d0
	;on ajoute 1
	addq.w	#1,d0
	rts


_RandomWord:
	bsr	_RandomByte
	rol.w   #8,d0
_RandomByte:
	move.b  $dff007,d0
	move.b  $bfd800,d1
	eor.b   d1,d0
	rts


;--- CALCULER LA TABLE DES NORMALES
CALCULER_TABLE_DES_NORMALES:
	lea	NORMALES(pc),a0
	lea	NORMALESCalculees(pc),a1
NBNormales=6
	move.l	#NBNormales-1,d7	;nb de polygones
.bcl1:
		;--- Calculer la normale du polygone
		move.w	(A0)+,d0	;nx
		move.w	(A0)+,d1	;ny
		move.w	(A0)+,d2	;nz
		bsr     Calculer_Y_Axes_Ax_AZ	;CalculerXYZ_3Axes ;renvoie D0=Y
		move.w	d0,(a1)		;ny2
		addq.l	#6,a1		;le pas est de 3.w
		;bpl		NormaleVersFond(pc)	;saute si d0>=0 cad normale orientee vers le fond
	dbf	d7,.bcl1
	rts


	
;--- CALCULER LES POLYGONES X,Z SANS Y
CALCULER_LES_POLYGONES_XZ:
	;calcule les Polygones uniquement en (x,z)
	;POLY:		dc.w	num_yY, Coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	;POLYCALCULES : dc.w 	Coul(1..6), A(x,z), B(x,z), C(x,z), D(x,z)
	;2020-12-01 : les POLYCALCULES sont enregistrés à la suite 
	;			  et non plus le reflet de la table POLY (evite les sauts et tests)
	
	lea		POLY(pc),a0
	lea		POLYCALCULES(pc),a1
	lea		NORMALESCalculees(pc),a3
	move.w	#-1,a4	;compteur de NB_POLY_CALCULES
	
	move.l	#NB_POLY-1,d7	;nb de polygones
BclCalculerPoints_XZ:
	move.w	(a0)+,d0	;numero de "normaleY"
	tst.w	(a3,d0)		;test du signe de la "normaleY"
	bpl	NormaleVersFond_XZ	;saute si d0>=0 cad normale orientee vers le fond
		add.w	#1,a4		;NB_POLY_CALCULES+1
		move.w	(a0)+,(a1)+	;copie de la couleur
	;-- point A
		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		;CALCUL ;MACRO évite le bsr  
		bsr	Calculer_XZ_3Axes	;utilisés D1..D5,A2 	;CalculerXYZ_3Axes(pc)
		;D3=X, D4=Z
		add.w	#offsetX,d3				;emplacement ecran
		add.w	#offsetZ,d4
		move.w  d3,(A1)+    ;x
		move.w  d4,(A1)+    ;z
	;-- point B
		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		;CALCUL ;MACRO évite le bsr  
		bsr	Calculer_XZ_3Axes	;CalculerXYZ_3Axes(pc)
		add.w	#offsetX,d3		;emplacement ecran
		add.w	#offsetZ,d4
		move.w  d3,(A1)+    ;x
		move.w  d4,(A1)+    ;z

	;-- point C
		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		;CALCUL ;MACRO évite le bsr   
		bsr	Calculer_XZ_3Axes	;CalculerXYZ_3Axes(pc)
		add.w	#offsetX,d3		;emplacement ecran
		add.w	#offsetZ,d4
		move.w  d3,(A1)+    ;x
		move.w  d4,(A1)+    ;z
	;-- point D (Vecteur AB=CD), gagne 50 HBL
		;---x
		add.w	-3*2*2(a1),d3	;X3+X1
		sub.w	-2*2*2(a1),d3	;X3+X1-X2
		move.w  d3,(a1)+   		;X4
		;---z
		add.w	-3*2*2(a1),d4
		sub.w	-2*2*2(a1),d4
		move.w  d4,(a1)+
	;-- Poly Suivant
		addq.l	#6,a0	;poly suivant
	dbf		d7,BclCalculerPoints_XZ
	bra		FinBclCalculerPoints_XZ	
NormaleVersFond_XZ:
		;on calcule pas
		lea 	13*2(a0),a0	;Polygone suivant
	dbf	d7,BclCalculerPoints_XZ
FinBclCalculerPoints_XZ:	
	move.w	a4,NB_POLY_CALCULES
	rts






;--- TRACER LES LIGNES DU RUBIKS SELON TABLE X Z (qui ne conteient pas Y)
TRACER_LIGNES_POLYGONES_XZ:

	IFNE AffLigneRUBIKS
	moveq.l	#0,d0
	WAITBLIT
	move.w	#40,BLTCMOD(A5)	;=largeur du plan de pixel en octets
	move.w	#40,BLTDMOD(A5)	;=largeur du plan de pixel en octets
	move.w	#$8000,BLTADAT(A5)
	move.w	#$FFFF,BLTBDAT(A5) 	:texture de la droite, $FFFF = pleine
	move.w	#$FFFF,BLTAFWM(A5)	;=$FFFF
	move.w	#$FFFF,BLTALWM(A5)	;=$FFFF
	lea		TableOctant(pc),a0

	;----- TRACE DU RUBIKS ---------
	;1polygone = dc.w    ny, coul, x1,y1,z1, , x2,y2,z2, x3,y3,z3, x4,y4,z4
	;POLYCALCULES : dc.w 	couleur (1..6), A(x,z), B(x,z), C(x,z), D(x,z)

	lea		POLYCALCULES(pc),a3
	move.w	NB_POLY_CALCULES(pc),d7
BoucleTracerRubiks_XZ:
		;on trace
		swap	d7
		move.w	(a3)+,d7	;couleur
		move.l	bitplaneB(pc),A1	;A1 et A2 utilisés comme copie dans la boucle
		;--- Couleur Plan0	
		btst	#0,d7	;couleur plan0
		beq	PasTracerPolyCouleurPlan0_XZ	
			;le plan est a afficher
			moveq.l	#0,d0	
			move.w	0(a3),d0	;x1
			move.w	2(a3),d1	;z1
			move.w	4(a3),d2	;x2
			move.w	6(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	4(a3),d0	;x1
			move.w	6(a3),d1	;z1
			move.w	8(a3),d2	;x2
			move.w	10(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	8(a3),d0	;x1
			move.w	10(a3),d1	;z1
			move.w	12(a3),d2	;x2
			move.w	14(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	12(a3),d0	;x1
			move.w	14(a3),d1	;z1
			move.w	0(a3),d2	;x2
			move.w	2(a3),d3	;z2
			bsr	TracerLignePleine
PasTracerPolyCouleurPlan0_XZ:
		lea	TAILLE_BITPLANE(a1),a1
		;--- Couleur Plan1
		btst	#1,d7	;couleur plan1
		beq	PasTracerPolyCouleurPlan1_XZ
			;le plan est a afficher
			moveq.l	#0,d0	
			move.w	0(a3),d0	;x1
			move.w	2(a3),d1	;z1
			move.w	4(a3),d2	;x2
			move.w	6(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	4(a3),d0	;x1
			move.w	6(a3),d1	;z1
			move.w	8(a3),d2	;x2
			move.w	10(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	8(a3),d0	;x1
			move.w	10(a3),d1	;z1
			move.w	12(a3),d2	;x2
			move.w	14(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	12(a3),d0	;x1
			move.w	14(a3),d1	;z1
			move.w	0(a3),d2	;x2
			move.w	2(a3),d3	;z2
			bsr	TracerLignePleine
PasTracerPolyCouleurPlan1_XZ:
		lea	TAILLE_BITPLANE(a1),a1
		;--- Couleur Plan2
		btst	#2,d7	;couleur plan1
		beq	PasTracerPolyCouleurPlan2_XZ
			;le plan est a afficher
			moveq.l	#0,d0	
			move.w	0(a3),d0	;x1
			move.w	2(a3),d1	;z1
			move.w	4(a3),d2	;x2
			move.w	6(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	4(a3),d0	;x1
			move.w	6(a3),d1	;z1
			move.w	8(a3),d2	;x2
			move.w	10(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	8(a3),d0	;x1
			move.w	10(a3),d1	;z1
			move.w	12(a3),d2	;x2
			move.w	14(a3),d3	;z2
			bsr	TracerLignePleine
			moveq.l	#0,d0
			move.w	12(a3),d0	;x1
			move.w	14(a3),d1	;z1
			move.w	0(a3),d2	;x2
			move.w	2(a3),d3	;z2
			bsr	TracerLignePleine
PasTracerPolyCouleurPlan2_XZ:
			lea		8*2(a3),a3
		swap	d7
		dbf	d7,BoucleTracerRubiks_XZ
	rts
	ENDC




;   ___ 
;  / __|
; | (__   
;  \___| SUB ROTATION
;


RotCour_ChargerTableTrigo:
	;--- CHARGER LES TABLES TRIGO
	;charges les angles
	;utilise
	;	a3,a4,a5,a6
	;SORTIE
	;	d3, d4, d5
	lea		Angles(pc),a2
	lea		CosSinTbl(pc),a3
	;A4=aX
	move.w	(a2)+,d3
    lsl.w	#2,d3		;aX
    move.l  (a3,d3),d3  ;cos(aX) sin(aX)
	;A5=aY
	move.w	(a2)+,d4
    lsl.w	#2,d4
  	move.l  (a3,d4),d4  ;cos(aY)
	;A6=aZ
	move.w	(a2)+,d5
	lsl.w	#2,d5
	move.l  (a3,d5),d5  ;cos(aZ) sin(aZ)
	rts

CalculerMatriceRotation:
	
	;d3 cos(aX)sin(aX)
	;d4 cos(aY)sin(aY)
	;d5 cos(aZ)sin(aZ)

	
	;1120 cycles
	;1074 réduction du nb de FIXDVAL 
	; 962 regroupement d'opérations SxSy et SxCy
	
	;P[X,Y,Z] = M * p[x,y,z]
	;M =
	;[SxSySz+CyCz	SxSyCz-CySz		CxSy	]
	;[CxSz			CxCz			-Sx		]
	;[SxCySz-SyCz	SxCyCz+SySz		CxCy	]	

	;pour des raisons de temps de cycles (affichage en X,Z)
	;le Y est placé en troisième position car pas forcement calculé
	;la matrice utilisée est M tel que P[X,Z,Y] = M * p[x,z,y]
	
	;---------------------------------------
	
	
	lea	MatriceRot(pc),a2

	;---------------------------------------
	;X=	+x*[SxSySz+CyCz]	+y*[SxSyCz-CySz]	+z*[CxSy]
	
					;		d3=CxSx d4=CySy d5=CzSz
	
	;SxSySz+CyCz
	move.w	d3,d0
	muls	d4,d0	;SxSy
	FIXEDVAL16x16 d0
	move.w	d0,d2	;SxSy pour plus bas afin
	muls	d5,d0	;SxSySz
	move.l	d5,d1
	swap	d1
	swap	d4		;		d3=CxSx d4=Sy<->Cy d5=CzSz
	muls	d4,d1	;CyCz
	add.l	d1,d0	;SxSySz+CyCz
	FIXEDVAL16x16 d0
	move.w	d0,(a2)+

	;SxSyCz-CySz
	move.w	d2,d0	;SxSy calculé plus haut
	swap	d5		;		d3=CxSx d4=SyCy d5=Sz<->Cz
	muls	d5,d0	;SxSyCz
	swap	d5		;		d3=CxSx d4=SyCy d5=Cz<->Sz
	move.w	d4,d1
	muls	d5,d1	;CySz
	sub.l	d1,d0	;SxSyCz-CySz
	FIXEDVAL16x16 d0
	move.w	d0,(a2)+

	;CxSy
	move.l	d3,d0
	swap	d0		;Cx
	swap	d4		;		d3=CxSx d4=Cy<->Sy d5=CzSz
	muls	d4,d0	;CxSy
	FIXEDVAL16x16 d0
	move.w	d0,(a2)+

	;---------------------------------------
	;Z=x*[SxCySz-SyCz]  +y*[SxCyCz+SySz] +z*CxCy
					;		d3=CxSx d4=CySy d5=CzSz
	;SxCySz-SyCz
	move.w	d3,d0	;Sx
	swap	d4		;		d3=CxSx d4=Sy<->Cy d5=CzSz
	muls	d4,d0	;SxCy
	FIXEDVAL16x16 d0
	move.w	d0,d2	;SxCy pour plus bas
	muls	d5,d0	;SxCySz
	swap	d5		;		d3=CxSx d4=SyCy d5=Sz<->Cz
	muls	d5,d2	;SxCyCz
	swap	d4		;		d3=CxSx d4=Cy<->Sy d5=SzCz
	move.w	d5,d1	;cZ
	muls	d4,d1	;SyCz
	sub.l	d1,d0	;SxCySz-SyCz
	FIXEDVAL16x16 d0
	move.w	d0,(a2)+
	
	;SxCyCz+SySz
	move.w	d4,d1	;Sy
	swap	d5		;		d3=CxSx d4=CySy d5=Cz<->Sz
	muls	d5,d1	;SySz
	add.l	d1,d2
	FIXEDVAL16x16 d2
	move.w	d2,(a2)+	;SxCyCz+SySz

	;CxCy 
	move.l	d3,d0
	swap 	d0		;Cx
	swap	d4		;		d3=CxSx d4=Sy<->Cy d5=CzSz
	muls	d4,d0	;CxCy
	FIXEDVAL16x16 d0
	move.w	d0,(a2)+;CxCy

					;		d3=CxSx d4=SyCy d5=CzSz

	;---------------------------------------
	;Y=x*CxSz	+y*CxCz	-z*Sx 

	;-Sx
	move.w	d3,d2	;Sx
	neg.w	d2
	lsl.l	#1,d2	;fixe 16 bits *
	swap 	d2		;-Sx
	;CxSz 
	swap	d3		;		d3=Sx<->Cx d4=SyCy d5=CzSz
	move.w	d3,d0	;Cx
	muls	d5,d0	;CxSz
	FIXEDVAL16x16 d0
	;CxCz
	move.w	d3,d1	;Cx
	swap	d5		;		d3=SxCx d4=SyCy d5=SzCz
	muls	d5,d1	;CxCz
	FIXEDVAL16x16 d1
	move.w	d0,(a2)+	;CxSz
	move.w	d1,(a2)+	;CxCz
	move.w	d2,(a2)		;-Sx

	;on remet les tables dans l'ordre (pas néecessaire)
	swap	d3
	swap	d4
	swap	d5

	rts

MatriceRot:
	dc.w	0,0,0
	dc.w	0,0,0
	dc.w	0,0,0




CalculerXYZ_3Axes:
	;676 cycles
	;= rotation selon 3 axes (x, y, z, aX, aY, aZ)
    ;Entree :   D0=x,  D1=y,  D2=Z
    ;           d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
    ;Sortie :   D2=D4=x, D0=y, D1=z
    ;Interne: 	A2,d6
	;************************
	;d0=X, d1=Y, d2=Z, d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
	;************************
	;rotation axe Z (plan XY)     
	move.w	d1,d6	;y
	muls	d5,d6	;y*sin(aZ)
	move.l	d6,a2
	move.w	d0,d6	;x
	swap 	d5		;cos(aZ).w
	muls	d5,d6	;x*cos(aZ)
	sub.l	a2,d6	;x1=x*cos(aZ)-y*sin(aZ)
	
	muls	d5,d1	;y*cos(aZ)
	swap	d5		;sin(aZ).w
	muls	d5,d0	;x*sin(aZ)
	add.l	d0,d1	;y1=x*sin(aZ)+y*cos(aZ)

	Swap 	d6
	rol.l	#2,d6	;x1
    Swap 	d1
	rol.l	#2,d1	;y1
    ;************************
    ;d0='' d6=x1 d1=y1, d2=Z, d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
    ;************************
	;rotation axe X (plan YZ)
	move.w	d2,d0	;z
	muls	d3,d0	;z*sin(aX)
	move.l	d0,a2
	move.w	d1,d0	;y1
	swap	d3		;cos(aX).w
	muls	d3,d0	;y1*cos(aX)
	sub.l	a2,d0	;y2=y1*cos(aX)-z*sin(ax) 
    
	muls    d3,d2	;z*cos(aX)
    swap	d3		;sin(aX).w
	muls    d3,d1	;y1*sin(aX)
    add.l   d1,d2   ;z1=y1*sin(aX)+z*cos(aX)
    
	Swap 	d0
	rol.l	#2,d0	;y2
    Swap 	d2
	rol.l	#2,d2	;z1
    ;************************
    ;d0=y2, d1='', d2=z1, d6=x1, d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
    ;************************
	;rotation axe Y (plan ZX)
    move.w  d6,d1	;x1
    muls    d4,d1	;x1*sin(aY)
	move.l	d1,a2
	move.w	d2,d1	;z1
	swap	d4		;cos(aY).w
    muls    d4,d1	;z1*cos(aY)
    sub.l   a2,d1   ;z2=z1*cos(aY)-x1*sin(aY)
    
	muls	d4,d6	;x1*cos(aY)
	swap	d4		;sin(aY).w
	muls	d4,d2	;z1*sin(aY)
    add.l   d6,d2   ;x2=z1*sin(aY)+x1*cos(aY)
    
	Swap 	d1
	rol.l	#2,d1
	Swap 	d2
	rol.l	#2,d2

    rts


Calculer_XZ_3Axes:
	;= rotation selon 3 axes (x, z, aX, aY, aZ)
    ;P(X,Z) = M * p(x,z,y)
	;************************
	;Entree :   D0=x, D1=y, D2=Z
    ;Sortie :   D3=X, D4=Z, D0,D1,D2 inchangés
    ;Interne: 	D5, A2
	;************************

	lea	MatriceRot(pc),a2
	
	move.w	(a2)+,d3	
	muls	d0,d3		;x*M[0,0]
	move.w	(a2)+,d4	
	muls	d1,d4		;y*M[1,0]
	add.l	d4,d3
	move.w	(a2)+,d4
	muls	d2,d4		;z*M[2,0]	
	add.l	d4,d3		
	Swap 	d3
	rol.l	#2,d3		;X
    
	move.w	(a2)+,d4	
	muls	d0,d4		;x*M[0,1]
	move.w	(a2)+,d5	
	muls	d1,d5		;y*M[1,1]
	add.l	d5,d4
	move.w	(a2)+,d5
	muls	d2,d5		;z*M[2,1]	
	add.l	d5,d4		
	Swap 	d4
	rol.l	#2,d4		;Z

	;Sortie :   D3=X, D4=Z
	rts
	
	;pour axe Z (futur dev)
	move.w	(a2)+,d5	
	muls	d0,d5		;x*M[0,2]
	move.w	(a2)+,d0	
	muls	d1,d0		;y*M[1,2]
	add.l	d5,d0
	move.w	(a2)+,d5
	muls	d2,d5		;z*M[2,2]	
	add.l	d5,d0		
	Swap 	d0
	rol.l	#2,d0		;Y

	;Sortie :   D2=x, D0=y, D1=z
	move.w	d3,d2
	move.w	d4,d1
	
	rts
	
	
	


	
 
Calculer_Y_Axes_Ax_AZ:
	;--- CALCULER NORMALE nY
	;nY = rotation selon 2 axes (aX,aZ) de (x, y, z)
	;utilisé pour le calcul de la normale nY, la rotation aY ne sert à rien
    ;Entree :   D0=x,  D1=y,  D2=Z
    ;           d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
    ;Sortie :   D0=normale.y
	;Utilises :	d0,d1,d2,d3,a2,a3,a4,a6
	;  
	;************************
	;d0=X, d1=Y, d2=Z, d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
	;************************
	;rotation axe Z (plan XY)     
	swap 	d5		;cos(aZ).w
	muls	d5,d1	;y*cos(aZ)
	swap	d5		;sin(aZ).w
	muls	d5,d0	;x*sin(aZ)
	add.l	d1,d0	;y1=x*sin(aZ)+y*cos(aZ)
    Swap 	d0
	rol.l	#2,d0	;y1
    ;************************
    ;d0='' d6=x1 d1=y1, d2=Z, d3=cos(ax)sin(ax), d4=cos(ay)sin(ay), d5=cos(az)sin(az)
    ;************************
	;rotation axe X (plan YZ)
	muls	d3,d2	;z*sin(aX)
	swap	d3		;cos(aX).w
	muls	d3,d0	;y1*cos(aX)
	swap	d3		;sin(aX).w
	sub.l	d2,d0	;y2=y1*cos(aX)-z*sin(ax) 
    Swap 	d0
	rol.l	#2,d0	;y2
	;Y=(x*sin(aZ)+y*cos(aZ))*cos(aX)-z*sin(ax)
	rts
		
	


CalculerXY_1Axe:
	;--- CALCULER X2, Y2
	;(x1,y1) = rotation selon axe (aZ) de (x, y)
    ;Entree :   D0=x,  D1=y
    ;           d5=cos(az)sin(az)
    ;Sortie :   d2=x1, d1=y1, d5=cos(az)sin(az)
    ;Interne: 	d3
	;************************
	;rotation axe Z (plan XY)     
	move.w	d1,d3	;y
	muls	d5,d3	;y*sin(aZ)

	move.w	d0,d2	;x
	swap 	d5		;cos(aZ).w
	muls	d5,d2	;x*cos(aZ)
	sub.l	d3,d2	;x1=x*cos(aZ)-y*sin(aZ)
	
	muls	d5,d1	;y*cos(aZ)
	swap	d5		;sin(aZ).w
	muls	d5,d0	;x*sin(aZ)
	add.l	d0,d1	;y1=x*sin(aZ)+y*cos(aZ)

	Swap 	d2
	rol.l	#2,d2	;x1
    Swap 	d1
	rol.l	#2,d1	;y1
	
	rts


;  _____ 
; |_   _|
;   | |  
;   |_|  TRACER AU BLITTER
;        



TracerLignePleine:
	;--- TRACER LIGNE PLEINE AU BLITTER	
	;Entree (d0=x1,d1=y1,d2=x2,d3=y2, a1=adresse du bitplane)
	;utilisés en lecture : a1, a5
	;        en écriture : d0..d6, a0, a1, a2

	move.l	a1,a2	;BitplaneB 
	
	; ------------------------------
	; BIT# BLTCON0     BLTCON1
	; ---- -------     -------
	; 15   START3      TEXTURE3
	; 14   START2      TEXTURE2
	; 13   START1      TEXTURE1
	; 12   START0      TEXTURE0
	; 11    1              0
	; 10    0              0
	; 09    1              0
	; 08    1              0
	; 07   LF7             0
	; 06   LF6            SIGN
	; 05   LF5             0 (Reserved)
	; 04   LF4            SUD
	; 03   LF3            SUL
	; 02   LF2            AUL
	; 01   LF1            SING
	; 00   LF0            LINE(=1) = LINE DRAW 
	
	;---- Calculer Octant ----
	moveq.l	#0,d4	;4 cycles
	sub.w	d1,d3	;d3=dy=y2-y1
	bpl.b	y2_sup_y1
	bset	#3,d4	;8 cycles
	neg.w	d3		;d3=abs(dy)
y2_sup_y1:
	sub.w	d0,d2	;d2=dx=x2-x1
	bpl.b	x2_sup_x1
	bset	#2,d4	
	neg.w	d2		;d2=abs(dx)
x2_sup_x1:
	cmp.w	d3,d2	;D3=dy vs D2=dx	
	bpl.b	dX_sup_dY
	bset	#1,d4
	exg		d2,d3
dX_sup_dY:
	;OLD move.b	(a0,d4),d5	;octant dans D5
	;d0=x1, d1=y1
	;d2=dx=GRAND DELTA, d3=dy=petit delta
	;d5=octant
	;--- Calculer Adresse de départ ----
	ror.l   #4,d0   ;move upper four bits into hi word
    add.w	d0,d0	;d0=d0*2 car d0 contient le nb de mots --> devient nb d'octets
	add.l	d0,a2	;bitplaneB+x1/8 modulo 16 pix (l'adressage étant sur 24 bits les 4 bits HI n'influent pas)
	lsl.w	#3,d1	;d1=y1*8
	add.w	d1,a2	;A2=bitplaneB+(x1/8)+y1*8
	add.w	d1,d1	;d1=y1*16
	add.w	d1,d1	;d1=y1*32
	add.l	d1,a2	;a2=bitplaneB+(x1/8)+y1*40 = adresse de départ	

	;NEW
	move.w	(a0,d4),d0	;octant dans D0.w

	moveq.l	#0,d6	;RAZ d6
	add.w   d3,d3	;d3=dy*2
    add.w   d3,d3	;d3=dy*4	;;lsl.w	#2,d3		;10 cycles
	move.w	D3,D4	;D4=4*dy
	
	move.w	d2,d1	;d1=d2=dX 
	
	add.w	#$01,d2	;dx+1
	lsl.w	#6,d2	;(dx+1)*64 ; 20 cycles
	add.w	#$02,d2	;(dx+1)*64+2
	
	add.w	d1,d1	;lsl.w	#1,d1	;D1=2*dx
	sub.w	d1,D3	;| d3=4*dy - 2*dx
	roxl.w	#7,D6	;| si D3<0, placer le bit SIGN à 1 dans BLTCON1 
	add.w	d1,d1	;D1=2*2dx
	
	or.w	d6,d0	;%xxxx000000xxxx01 ;bit 1 = 1 point par ligne 
					;dans Tableoctant pour éviter bset #1,d5
	swap	d0
	or.w	d6,D0	
	or.w	#$0BCA,D0
	swap	d0
	WAITBLIT
	move.l	d0,BLTCON0(A5)	;charger BLTCON0 et BLTCON1 en m
	;move.w	d0,BLTCON0(A5)	;bits 15,14,13,12  = point de départ de la droite
	;move.w	d5,BLTCON1(A5)	;bits 15,14,13, 12  = point de départ de la droite
	move.w	d4,BLTBMOD(A5)	;=4*dy
	move.l	d3,BLTAPTH(A5)	;=4*dY-2*dX, 
	sub.w	d1,D4			;d4=4*dy-4*dx
	move.w	d4,BLTAMOD(A5)	;=4*dy-4*dx
	move.l	a2,BLTCPTH(A5)	;adresse du point de départ de la droite
	move.l	a2,BLTDPTH(A5)	;idem
	move.w	d2,BLTSIZE(A5)	;c'est parti = (dX+1)*64+2
	rts	
	
	
TableOctant:	;3 premiers bits=octant, bit1 = 1 si 1 pt /ligne, bit 0=1 mode tracé de ligne
	dc.w	%10001
	dc.W	%00001
	dc.w	%10101
	dc.w	%01001
	dc.w	%11001
	dc.w	%00101
	dc.w	%11101
	dc.w	%01101
	even




;--- EFFACER BITPLANE C	-------------------
	;
	OffsetOctetRAZBLT=(((offsetZ-RayonMaxi)*DISPLAY_DX)+(offsetX-RayonMaxi))/8
Effacer_BitPlaneC:
	;--- effacement complet (152 HBL)
	; move.w	#0,BLTDMOD(a5)
	; move.w	#$0000,BLTCON1(a5)
	; move.w	#%0000000100000000,BLTCON0(a5)
	; move.l	bitplaneC,BLTDPTH(a5)
	; move.w	#(DISPLAY_DX>>4)!(DISPLAY_DY<<6),BLTSIZE(a5)
	jsr		Effacer_BitPlaneC0(pc)
	jsr		Effacer_BitPlaneC1(pc)
	jsr		Effacer_BitPlaneC2(pc)
	rts
	
	;--- Effacement selectif = rubiks seul
	;RayonMaxi=92
	;offsetX=160
	;offsetZ=100
	;TAILLE_BITPLANE=((DISPLAY_DX*DISPLAY_DY)>>3)
	
Effacer_BitPlaneC0:
	move.l	bitplaneC(pc),a0
	WAITBLIT
	move.w	#$0000,BLTCON1(a5)
	move.w	#%0000000100000000,BLTCON0(a5)
	lea		OffsetOctetRAZBLT(a0),a0	;adresse de départ
	move.l	a0,BLTDPTH(a5)
	move.w	#(display_DX-(RayonMAxi*2))/8,BLTDMOD(a5)
	move.w	#((RayonMaxi*2)>>4)!((RayonMaxi*2)<<6),BLTSIZE(a5)
	rts
Effacer_BitPlaneC1:	
	move.l	bitplaneC(pc),a0
	WAITBLIT
	move.w	#$0000,BLTCON1(a5)
	move.w	#%0000000100000000,BLTCON0(a5)
	lea		OffsetOctetRAZBLT+TAILLE_BITPLANE(a0),a0	;adresse de départ
	move.l	a0,BLTDPTH(a5)
	move.w	#(display_DX-(RayonMAxi*2))/8,BLTDMOD(a5)
	move.w	#((RayonMaxi*2)>>4)!((RayonMaxi*2)<<6),BLTSIZE(a5)
	rts
Effacer_BitPlaneC2:
	move.l	bitplaneC(pc),a0
	WAITBLIT
	move.w	#$0000,BLTCON1(a5)
	move.w	#%0000000100000000,BLTCON0(a5)
	lea		OffsetOctetRAZBLT+2*TAILLE_BITPLANE(a0),a0	;adresse de départ
	move.l	a0,BLTDPTH(a5)
	move.w	#(display_DX-(RayonMAxi*2))/8,BLTDMOD(a5)
	move.w	#((RayonMaxi*2)>>4)!((RayonMaxi*2)<<6),BLTSIZE(a5)
	rts



;--- TRACER ET EFFACER DEBUG ANGLE -------------------
;
	IFNE DEBUGDISPLAY_TIME
;
DEBUG_AngleCentreX=288	;18*16
DEBUG_AngleCentreY=17
DEBUG_AngleRayon=16		;rayon de l'indicateur
DEBUG_AnglePasY=32		;pas entre 2 centres
;
DEBUG_AngleX1=DEBUG_AngleCentreX-DEBUG_AngleRayon
DEBUG_AngleY1=DEBUG_AngleCentreY-DEBUG_AngleRayon
DEBUG_AngleX2=DEBUG_AngleCentreX+DEBUG_AngleRayon
DEBUG_AngleY2=DEBUG_AngleCentreY+(2*DEBUG_AnglePasY)+DEBUG_AngleRayon+1
DEBUG_ANGLEOffsetOctetRAZBLT=(((DEBUG_AngleY1)*DISPLAY_DX)+(DEBUG_AngleX1))/8
;
DEBUG_AngleModulo=(display_DX-(DEBUG_AngleRayon*2))/8
DEBUG_AngleDeltaX=DEBUG_AngleX2-DEBUG_AngleX1
DEBUG_AngleDeltaY=DEBUG_AngleY2-DEBUG_AngleY1
;
Tracer_DEBUG_ANGLE:			
		move.l	bitplaneB(pc),A1	;A1 et A2 utilisés comme copie dans la boucle	

		lea	CosSinTbl(pc),a3
		
		lea	AngleAx(pc),a6
		moveq.l	#3-1,d7
	BoucleAffAngles:
			move.l	#DEBUG_AngleCentreX,d0	;x1
			move.l	#DEBUG_AngleCentreY,d1	;y1
			move.l	#DEBUG_AngleRayon-1,d4	;rayon
			
			;ajout du pas y
			moveq.l	#0,d5
			move.w	d7,d5
			muls	#DEBUG_AnglePasY,d5
			add.w	d5,d1
			
			moveq.l	#0,d5
			move.w	(a6)+,d5	;angle AX, AY, AZ
			add.w	d5,d5		;angle*2 
			add.w	d5,d5		;angle*4 
			move.l	(a3,d5),d2	;COS(a) SIN(a)
			move.w	d2,d3		;d3.w = sin(a)
			swap 	d2			;d2.w = cos(a)
			
			muls	d4,d2		;r*cos(a)
			lsr.l	#7,d2		
			lsr.l	#7,d2 		;x2
			add.l	d0,d2

			muls	d4,d3		;r*SIN(a)
			lsr.l	#7,d3
			lsr.l	#7,d3		;y2
			add.l	d1,d3
			
			bsr	TracerLignePleine
			
			
		dbf	d7,BoucleAffAngles

	; move.l	#32-1,d7
; BCLTRacer:
	; move.l	d7,d0
	; mulu	#10,d0
	; move.l	#0,d1
	; move.l	d0,d2
	; move.l	#255,d3
	; bsr	TracerLignePleine(pc)
	; dbf	d7,BCLTracer

	rts
	
	
Effacer_Debug_Angle:	
	move.l	bitplaneC(pc),a0
	lea		DEBUG_ANGLEOffsetOctetRAZBLT(a0),a0	;adresse de départ
	WAITBLIT
	move.w	#$0000,BLTCON1(a5)
	move.w	#%0000000100000000,BLTCON0(a5)
	move.l	a0,BLTDPTH(a5)
	move.w	#DEBUG_AngleModulo,BLTDMOD(a5)
	move.w	#((DEBUG_AngleDeltaX)>>4)!((DEBUG_AngleDeltaY)<<6),BLTSIZE(a5)
	rts
	ENDC





AFFICHER_TEXTES:
	AFFTEXTE 0,0,"Rubiks 3D - Arnaud - 2021-02-26" ;MACRO : x,y,"texte"
	AFFTEXTE 0,1,"Amiga68000@gmail.com" ;MACRO : x,y,"texte"
	
	
	rts



;--- Afficher un Texte 8x8 
;A2=adresse dans le bitplane
;A3=adresse du texte à afficher,0
;utilisé : d0, a0, a1
AfficherTexte8x8:	;conso 89 HBL
	lea		font8(pc),a1
.bcl:
	moveq.l	#0,d0
	move.b	(a3)+,d0	;on lit le caratère
.bcl2:
	sub.b	#$20,d0		;la table commence au caractère " "
	lsl.w	#3,d0		;8 octets / caractère
	lea		(a1,d0),a0	;a0=a1+d0
	moveq.l	#8-1,d0
.aff8x8:
	move.b	(A0)+,(A2)
	lea		(DISPLAY_DX>>3)(a2),a2	;ligne suivante
	dbf		d0,.aff8x8
	;fin de cara
	;sub.l	#(DISPLAY_DX>>3)*8-1,a2	;position car suivant
	lea     -((DISPLAY_DX>>3)*8-1)(a2),a2
	moveq.l	#0,d0
	move.b	(a3)+,d0	;on lit le caratère
	bne		.bcl2		;si 0 on est  la fin du texte
.fin:
	rts







;--- Reserver la memoire
TAILLE_FONT16 = 256<<5

ReserverMemoireCHIP:
	;Memoire pour copperlist et bitPlanes
	; move.l	#TAILLE_MEM_RESERVEE,d0
	; move.l	#$10002,d1
	; jsr		AllocMem(a6)
	; move.l	d0,copperlist_PTR
	; beq	ErrorMem
	; ;calcul du pointeur BitPlanes de la copperList
	; move.l	d0,d1
	; add.l	#CplBitPlanes-CopListDataStart,d1
	; move.l	d1,Copperlist_BitPlanes_PTR
	; add.l	#COPSIZE,d0
	; move.l	d0,bitplaneA
	; add.l	#DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	; move.l	d0,bitplaneB
	; add.l	#DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	; move.l	d0,bitplaneC
	
	;memoire pour la police de caractères

	move.l #TAILLE_FONT16,d0
	move.l #$10002,d1
	jsr AllocMem(a6)
	move.l d0,Font16_PTR
	rts

;--- Libérer la mémoire
LibererMemoireCHIP:
	;Copper et bitplane
	; movea.l Copperlist_PTR(pc),a1
	; move.l #TAILLE_MEM_RESERVEE,d0
	; jsr FreeMem(a6)
	;font 16
	movea.l 	Font16_PTR,a1
	move.l 	#TAILLE_FONT16,d0
	jsr 	FreeMem(a6)
	rts


;--- Couper et Restaurer le Hardware
CouperHardware:
	;Couper le système multi-taches
	jsr Forbid(a6)
	;Couper le hardware
	move.w INTENAR(a5),intena_PTR
	move.w #$7FFF,INTENA(a5)
	move.w INTREQR(a5),intreq_PTR
	move.w #$7FFF,INTREQ(a5)
	move.w DMACONR(a5),dmacon_PTR
	move.w #$07FF,DMACON(a5)
	rts
RestaurerHardware:
	movea.l $4.w,a6
	;Couper le hardware
	move.w #$7FFF,INTENA(a5)
	move.w #$7FFF,INTREQ(a5)
	move.w #$07FF,DMACON(a5)
	;Rétablir le hardware
	move.w dmacon_PTR,d0
	bset #15,d0
	move.w d0,DMACON(a5)
	move.w intreq_PTR,d0
	bset #15,d0
	move.w d0,INTREQ(a5)
	move.w intena_PTR,d0
	bset #15,d0
	move.w d0,INTENA(a5)
	;Rétablir la Copper list
	lea graphicslibrary(pc),a1
	jsr	OldOpenLibrary(a6) ;-408
	move.l d0,a1
	move.l 38(a1),COP1LCH(a5)
	clr.w COPJMP1(a5)
	jsr CloseLib(a6) ;-414
	;Rétablir le système multi-taches
	jsr Permit(a6) 
	rts

;--- Creer et activer la Copper list ----------
InitiliserCopperList:
	;copie les adresses des 3 premiers bitplanes dans copperlist
	moveq	#DISPLAY_DEPTH-1,d1
	move.l 	#bitplaneA,a0
	move.l	#CplBitPlanes,a1	;adresse de CplBitPlanes
	add.l	#2,a1
.l:	
	move.l	(a0)+,d0	;adresse du pitplane
	move.w	d0,(a1)		;poids faible
	swap	d0	
	add.l	#4,a1
	move.w	d0,(a1)		;poids fort
	add.l	#4,a1
	add.l	#TAILLE_BITPLANE,a0 ;plan suivant du bitplaneA
	dbf		d1,.l
	
	; ;transferer la copperlist en Chip
	; move.l	#COPSIZE/4-1,d0
	; move.l	#CopListDataStart,a0
	; move.l	copperlist_PTR,a1
; .l2:
	; move.l	(a0)+,(a1)+
	; dbf		d0,.l2
	; ;Activer la Copper list
	;move.l copperlist_PTR,COP1LCH(a5)
	
	move.l	#CopListDataStart,COP1LCH(a5) ;
	clr.w 	COPJMP1(a5)
	move.w 	#$83C0,DMACON(a5)	;DMAEN=1, COPEN=1, BPLEN=1, COPEN=1, BLTEN=1
	rts


;---------- Création d'une police 16x16 à partir d'une police 8x8 ----------
CreerPolice16x16:
	;Préparer les données de la police
	;1er  octet = suite des bits 7 des 8 lignes / octets du caractère, 
	;2ème octet = suite des bits 6 des 8 lignes / octets du caractère, etc. 
	;rotation de -90°). 
	;Noter qu'au Blitter il faudra donc tracer les colonnes de la dernière à la première ligne 
	;du fait de l'orientation du motif.
	;il faudrait lui appliquer une symétrie d'axe Y avant pour tracer de la première à la dernière ligne
	lea 	font8(pc),a0
	move.l 	Font16_PTR(pc),a1
	move.w 	#256-1,d0
_fontLoop:
	moveq 	#7,d1		;
_fontLineLoop:
	clr.w 	d5
	clr.w 	d3
	clr.w 	d4
_fontColumnLoop:
	move.b 	(a0,d5.w),d2	;
	btst 	d1,d2		;on teste le bit D1
	beq 	_fontPixelEmpty
	bset 	d4,d3		;
	addq.b 	#1,d4
	bset 	d4,d3
	addq.b 	#1,d4
	bra 	_fontPixelNext
_fontPixelEmpty:
	addq.b 	#2,d4
_fontPixelNext:
	addq.b 	#1,d5
	btst 	#4,d4
	beq 	_fontColumnLoop
	move.w 	d3,(a1)+
	move.w 	d3,(a1)+
	dbf 	d1,_fontLineLoop
	lea 	8(a0),a0
	dbf 	d0,_fontLoop
	rts





;  _   _                               _     ___          _         
; | | | |  _ _    _  _   ___  ___   __| |   / __|  _  _  | |__   ___
; | |_| | | ' \  | || | (_-< / -_) / _` |   \__ \ | || | | '_ \ (_-<
;  \___/  |_||_|  \_,_| /__/ \___| \__,_|   |___/  \_,_| |_.__/ /__/
;

Assembly=0
	IFNE Assembly	;ne pas assembler


	ENDC



;  ___      _     _____     _   
; |   \    /_\   |_   _|   /_\  
; | |) |  / _ \    | |    / _ \ 
; |___/  /_/ \_\   |_|   /_/ \_\
;
;---------- Données ----------


;--- COMPTEUR WAITBLIT
	IFNE CTR
CTRWait:	dc.l	0
	ENDC
	
	
graphicslibrary:
	DC.B "graphics.library",0
	EVEN
font8:	INCBIN "sources:sinescroll/font8.fnt"	;32 à 127
	EVEN
Texte_Char:	
	DC.B 	"Quelle satisfaction de refaire de l'assembleur 68000 ! ... ",0
	dc.b	"Bug si affiche",0
	EVEN
			
TEXT_POS:			dc.l	0
dmacon_PTR:			DC.w	0
intena_PTR:			DC.w	0
intreq_PTR:			DC.w	0
scrollColumn:		DC.W	0
scrollChar:			DC.W	0
angle:				DC.W	0
copperlist_PTR:		DC.L 	CopListDataStart
Copperlist_BitPlanes_PTR:	dc.l	CplBitPlanes
Font16_PTR:			DC.L 	0
bitplaneA:			DC.L 	ScreenA
bitplaneB:			DC.L 	ScreenB
bitplaneC:			DC.L 	ScreenC






;  _____   ___   ___    ___    ___  
; |_   _| | _ \ |_ _|  / __|  / _ \ 
;   | |   |   /  | |  | (_ | | (_) |
;   |_|   |_|_\ |___|  \___|  \___/ 
;----- Tables Trigo -----


;---- Angles de rotation objet
Angles:
AngleAx:		dc.w	InitAngleAx
AngleAy:		dc.w	InitAngleAy
AngleAz:		dc.w	InitAngleAz

CosSinTbl:
   dc.l   $40000000,$3FFD011D,$3FF6023B,$3FE90359,$3FD80476,$3FC10593,$3FA606B0,$3F8507CC,$3F6008E8,$3F360A03   ;cos(0) sin(0)
   dc.l   $3F070B1D,$3ED20C36,$3E990D4E,$3E5C0E65,$3E190F7B,$3DD11090,$3D8511A4,$3D3412B6,$3CDE13C6,$3C8314D6   ;cos(10) sin(10)
   dc.l   $3C2315E3,$3BBF16EF,$3B5617F9,$3AE91901,$3A771A07,$3A001B0C,$39851C0E,$39061D0E,$38821E0B,$37F91F07   ;cos(20) sin(20)
   dc.l   $376C1FFF,$36DB20F6,$364621EA,$35AC22DB,$350E23C9,$346C24B5,$33C6259E,$331C2684,$326E2766,$31BC2846   ;cos(30) sin(30)
   dc.l   $31062923,$304D29FC,$2F8F2AD3,$2ECE2BA5,$2E092C75,$2D412D41,$2C752E09,$2BA52ECE,$2AD32F8F,$29FC304D   ;cos(40) sin(40)
   dc.l   $29233106,$284631BC,$2766326E,$2684331C,$259E33C6,$24B5346C,$23C9350E,$22DB35AC,$21EA3646,$20F636DB   ;cos(50) sin(50)
   dc.l   $2000376C,$1F0737F9,$1E0B3882,$1D0E3906,$1C0E3985,$1B0C3A00,$1A073A77,$19013AE9,$17F93B56,$16EF3BBF   ;cos(60) sin(60)
   dc.l   $15E33C23,$14D63C83,$13C63CDE,$12B63D34,$11A43D85,$10903DD1,$0F7B3E19,$0E653E5C,$0D4E3E99,$0C363ED2   ;cos(70) sin(70)
   dc.l   $0B1D3F07,$0A033F36,$08E83F60,$07CC3F85,$06B03FA6,$05933FC1,$04763FD8,$03593FE9,$023B3FF6,$011D3FFD   ;cos(80) sin(80)
   dc.l   $00004000,$FEE23FFD,$FDC43FF6,$FCA63FE9,$FB893FD8,$FA6C3FC1,$F94F3FA6,$F8333F85,$F7173F60,$F5FC3F36   ;cos(90) sin(90)
   dc.l   $F4E23F07,$F3C93ED2,$F2B13E99,$F19A3E5C,$F0843E19,$EF6F3DD1,$EE5B3D85,$ED493D34,$EC393CDE,$EB293C83   ;cos(100) sin(100)
   dc.l   $EA1C3C23,$E9103BBF,$E8063B56,$E6FE3AE9,$E5F83A77,$E4F33A00,$E3F13985,$E2F13906,$E1F43882,$E0F837F9   ;cos(110) sin(110)
   dc.l   $E000376C,$DF0936DB,$DE153646,$DD2435AC,$DC36350E,$DB4A346C,$DA6133C6,$D97B331C,$D899326E,$D7B931BC   ;cos(120) sin(120)
   dc.l   $D6DC3106,$D603304D,$D52C2F8F,$D45A2ECE,$D38A2E09,$D2BE2D41,$D1F62C75,$D1312BA5,$D0702AD3,$CFB229FC   ;cos(130) sin(130)
   dc.l   $CEF92923,$CE432846,$CD912766,$CCE32684,$CC39259E,$CB9324B5,$CAF123C9,$CA5322DB,$C9B921EA,$C92420F6   ;cos(140) sin(140)
   dc.l   $C8932000,$C8061F07,$C77D1E0B,$C6F91D0E,$C67A1C0E,$C5FF1B0C,$C5881A07,$C5161901,$C4A917F9,$C44016EF   ;cos(150) sin(150)
   dc.l   $C3DC15E3,$C37C14D6,$C32113C6,$C2CB12B6,$C27A11A4,$C22E1090,$C1E60F7B,$C1A30E65,$C1660D4E,$C12D0C36   ;cos(160) sin(160)
   dc.l   $C0F80B1D,$C0C90A03,$C09F08E8,$C07A07CC,$C05906B0,$C03E0593,$C0270476,$C0160359,$C009023B,$C002011D   ;cos(170) sin(170)
   dc.l   $C0000000,$C002FEE2,$C009FDC4,$C016FCA6,$C027FB89,$C03EFA6C,$C059F94F,$C07AF833,$C09FF717,$C0C9F5FC   ;cos(180) sin(180)
   dc.l   $C0F8F4E2,$C12DF3C9,$C166F2B1,$C1A3F19A,$C1E6F084,$C22EEF6F,$C27AEE5B,$C2CBED49,$C321EC39,$C37CEB29   ;cos(190) sin(190)
   dc.l   $C3DCEA1C,$C440E910,$C4A9E806,$C516E6FE,$C588E5F8,$C5FFE4F3,$C67AE3F1,$C6F9E2F1,$C77DE1F4,$C806E0F8   ;cos(200) sin(200)
   dc.l   $C893E000,$C924DF09,$C9B9DE15,$CA53DD24,$CAF1DC36,$CB93DB4A,$CC39DA61,$CCE3D97B,$CD91D899,$CE43D7B9   ;cos(210) sin(210)
   dc.l   $CEF9D6DC,$CFB2D603,$D070D52C,$D131D45A,$D1F6D38A,$D2BED2BE,$D38AD1F6,$D45AD131,$D52CD070,$D603CFB2   ;cos(220) sin(220)
   dc.l   $D6DCCEF9,$D7B9CE43,$D899CD91,$D97BCCE3,$DA61CC39,$DB4ACB93,$DC36CAF1,$DD24CA53,$DE15C9B9,$DF09C924   ;cos(230) sin(230)
   dc.l   $DFFFC893,$E0F8C806,$E1F4C77D,$E2F1C6F9,$E3F1C67A,$E4F3C5FF,$E5F8C588,$E6FEC516,$E806C4A9,$E910C440   ;cos(240) sin(240)
   dc.l   $EA1CC3DC,$EB29C37C,$EC39C321,$ED49C2CB,$EE5BC27A,$EF6FC22E,$F084C1E6,$F19AC1A3,$F2B1C166,$F3C9C12D   ;cos(250) sin(250)
   dc.l   $F4E2C0F8,$F5FCC0C9,$F717C09F,$F833C07A,$F94FC059,$FA6CC03E,$FB89C027,$FCA6C016,$FDC4C009,$FEE2C002   ;cos(260) sin(260)
   dc.l   $FFFFC000,$011DC002,$023BC009,$0359C016,$0476C027,$0593C03E,$06B0C059,$07CCC07A,$08E8C09F,$0A03C0C9   ;cos(270) sin(270)
   dc.l   $0B1DC0F8,$0C36C12D,$0D4EC166,$0E65C1A3,$0F7BC1E6,$1090C22E,$11A4C27A,$12B6C2CB,$13C6C321,$14D6C37C   ;cos(280) sin(280)
   dc.l   $15E3C3DC,$16EFC440,$17F9C4A9,$1901C516,$1A07C588,$1B0CC5FF,$1C0EC67A,$1D0EC6F9,$1E0BC77D,$1F07C806   ;cos(290) sin(290)
   dc.l   $1FFFC893,$20F6C924,$21EAC9B9,$22DBCA53,$23C9CAF1,$24B5CB93,$259ECC39,$2684CCE3,$2766CD91,$2846CE43   ;cos(300) sin(300)
   dc.l   $2923CEF9,$29FCCFB2,$2AD3D070,$2BA5D131,$2C75D1F6,$2D41D2BE,$2E09D38A,$2ECED45A,$2F8FD52C,$304DD603   ;cos(310) sin(310)
   dc.l   $3106D6DC,$31BCD7B9,$326ED899,$331CD97B,$33C6DA61,$346CDB4A,$350EDC36,$35ACDD24,$3646DE15,$36DBDF09   ;cos(320) sin(320)
   dc.l   $376CDFFF,$37F9E0F8,$3882E1F4,$3906E2F1,$3985E3F1,$3A00E4F3,$3A77E5F8,$3AE9E6FE,$3B56E806,$3BBFE910   ;cos(330) sin(330)
   dc.l   $3C23EA1C,$3C83EB29,$3CDEEC39,$3D34ED49,$3D85EE5B,$3DD1EF6F,$3E19F084,$3E5CF19A,$3E99F2B1,$3ED2F3C9   ;cos(340) sin(340)
   dc.l   $3F07F4E2,$3F36F5FC,$3F60F717,$3F85F833,$3FA6F94F,$3FC1FA6C,$3FD8FB89,$3FE9FCA6,$3FF6FDC4,$3FFDFEE2   ;cos(350) sin(350)

   dc.l   $40000000,$3FFD011D,$3FF6023B,$3FE90359,$3FD80476,$3FC10593,$3FA606B0,$3F8507CC,$3F6008E8,$3F360A03   ;cos(0) sin(0)









;  ___         _        ___                    
; | _ \  ___  | |_     / __|  ___   _  _   _ _ 
; |   / / _ \ |  _|   | (__  / _ \ | || | | '_|
; |_|_\ \___/  \__|    \___| \___/  \_,_| |_|  
; Routines de rotation de couronne
;



RotCour_DATA_ROTATION:
RotCour_DATA_AxeRotation:		dc.w	ay2
RotCour_DATA_VitessDeRotation:	dc.w	-1
RotCour_DATA_ValeurDeRotation:	dc.w	0




RotCour_SEQ_Demarrer_Rotation:
	;-- CREER UN ORDRE DE ROTATION
	;	A la demande : démarrer une rotation de couronne
	;	Spécifier un angle, un sens et un axe de rotation
	;	initialiser le séquensseur
	lea		SEQUENCES_ROTATION(pc),a0
	tst.l	(a0)
	bne		.lblFIN		;une rotation est en cours
	;-- initialiser la rotation Horaire de aX1
	lea		RotCour_DATA_ROTATION(pc),a0
	move.w	#az1,(a0)+	;AxeDeRotation
	move.w	#2,(a0)+	;VitessDeRotation
	move.w	#0,(a0)		;ValeurDeRotation 360 si v=-1
	;--  Passe la SEQ à 1
	jsr		RotCour_SEQ_SUIVANTE(pc)
.lblFIN
	rts
	


RotCour_SEQ_Demarrer_RotationALEATOIRE:
	;-- CREER UN ORDRE DE ROTATION ALEATOIRE
	lea		SEQUENCES_ROTATION(pc),a0
	tst.l	(a0)
	bne		.lblFIN		;une rotation est en cours
	lea		RotCour_DATA_ROTATION(pc),a0
	jsr		Aleatoire1A6	;D0=1..6 ; d0, d1, d2
	move.w	d0,(a0)+	;AxeDeRotation 1..6
	move.w	#-5,(a0)+	;VitessDeRotation
	move.w	#360,(a0)		;;ValeurDeRotation 360 si v=-1
	;--  Passe la SEQ à 1
	jsr		RotCour_SEQ_SUIVANTE(pc)
.lblFIN
	rts



	
;--- GERER ROTATION COURONNE
;sub à appeler à chaque VBL qui gère 
;le sequencement automatiquement
;de la rotation de couronne
GERER_ROTATION_COURONNE:
	;
	lea		SEQUENCES_ROTATION(pc),a0
	move.l	(a0),d0
	beq		FIN_GERER_ROTATION_COURONNE
	;non vide, il y a un ordre
	add.l	d0,d0
	add.l	d0,d0	;decalage
	add.l	d0,a0
	move.l	(a0),a0	;charge l'offset adresse de la table SEQ
	lea		Jump(pc),a1
	add.l	a1,a0	;adresse de saut
Jump:
	jmp		(a0)
FIN_GERER_ROTATION_COURONNE:
	rts

RotCour_SEQ_SUIVANTE:
	lea		SEQUENCES_ROTATION(pc),a0
	add.l	#1,(a0)
	rts
	
RotCour_SEQ_STOP:
	lea		SEQUENCES_ROTATION(pc),a0
	move.l	#0,(a0)
	rts
	
SEQUENCES_ROTATION:
	dc.l	0	;n°séquence exécutée à chaque VBL
	;offset des séquences :
	dc.l	RotCour_INIT_Couronne-Jump
	dc.l	RotCour_TournerCouronne-Jump
	dc.l	RotCour_FinaliserRotationCouronne-Jump
	dc.l	RotCour_SEQ_STOP-Jump



;  ___ 
; |_ _|
;  | | 
; |___| INITILISER ROTATION DE COURONNE
;





;-- SAUVER LES POLYGONES DE LA COURONNE
	;pour chaque pièce correspondant à l'axe de rotation couronne
	;copier POLY dans POLY_SAUVE
	;identifier les Numeros de normales impactés
;-- CONFIGURER LES NORMALES DES POLYGONNES EN ROTATION
	;dans POLY_SAUVE et dans POLY
	;pour chaque polygone de la couronne
	;changer numNormale pour numNORMALESCouronnes 
	;NORMALESCouronnes = f(RotCour_Normales_A_Sauver)
;-- SEQUENCE SUIVANTE


RotCour_INIT_Couronne:

	bsr		RotCour_INIT_CompterAxesEtIdentifierPOLY
	bsr		RotCour_INIT_CreerNormalesCouronne
	;bsr		RotCour_INIT_CreerTablePtrNormalesCouronneVsPOLYSauve
	bsr		RotCour_INIT_CreerPolySauve
	jsr		RotCour_SEQ_SUIVANTE(pc)
	rts


	


RotCour_INIT_CompterAxesEtIdentifierPOLY:
;TEST OK
;//TODO voir à éviter de compter les axes
;car si rot ax1, alors tous les axes impactés sauf ax2

	;-- Compter les AXES, enregistrer l'adresse POLY
	;Mettre à 0 la table des 6 Numeros de normales 
	;
	;ENTREE:
	;RotCour_DATA_AxeRotation: dc.w	Axe de rotation
	;
	;SORTIES:
	;
	;RotCour_Normales_A_Sauver:
	;dc.w	9,3,3,0,3,3	;nb de fois que les axes sont comptés
	;
	;POLY_SAUVES:
	;dc.w	ptr POLY, axe , 0, ...,0
	;...
	;dc.w	ptr POLY, axe , 0, ...,0

	;Mettre à 0 la table des 6 Numeros de normales 
	lea		RotCour_Normales_A_Sauver(pc),a4
	move.l	#0,(a4)+
	move.l	#0,(a4)+
	move.l	#0,(a4)
	;
	move.w	RotCour_DATA_AxeRotation,d0	;axe de rotation
	lea		PIECE(pc),a0
	lea		POLY_SAUVES(pc),a2
	move.w	#NB_PIECE-1,d7	;26 pièces
	;PIECE:	dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, aX2,aY2,aZ2
.bcl1:
		move.l	a0,a3			;ptr PIECE
		move.w	(a3),d1			;nb de Poly de la pièce
		add.l	#4*2,a3			;ptr PIECE.1erAxe
		sub.w	#1,d1			;init compteur pour dbf
.bcl2:
			move.w	(a3)+,d2	;PIECE.axe
			cmp.w	d2,d0		;PIECE.axe = AxeRotation ?
			bne		.bcl4
			;PIECE.axe = AxeRotation
			;l'axe est présent, la pièce est concernée
			
			move.l	a0,a3		
			move.w	(a3)+,d2	;nb de Poly de la pièce
			sub.w	#1,d2
.bcl3:
				;-- Traitement 1 Polygone
				;on enregistre l'adresse POLY dans chaque début de POLY_SAUVE
				lea		POLY(pc),a1
				moveq.l	#0,d3
				move.w	(a3)+,d3	;ofsset Pxxx-POLY
				add.l	d3,a1		;ptr de Pxxx
				move.l	a1,(a2)+	;adresse du Pxxx de table POLY dans POLY_SAUVE
				;
				moveq.l	#0,d4
				move.w	4(a3),d4	;lecture de l'axe
				move.w	d4,(a2)		;Axe dans POLY_SAUVE
				add.l	#TAILLE_1_POLY_SAUVE-4,a2
				;on ajoute 1 à la normale utilisée
				lea		RotCour_Normales_A_Sauver(pc),a4
				subq.w	#1,d4		;axe(1..6) --> (0..5)
				add.w	d4,d4		;pointeur axe.w
				add.l	d4,a4		;ptr sur CTR axe (ou CTR normale)
				add.w	#1,(a4)		;ajoute 1 à CTR de normale à sauver
			dbf		d2,.bcl3	;poly Suivant
			bra		.bcl5
.bcl4:
		dbf	d1,.bcl2	;test axe suivant
.bcl5:
		add.l	#7*2,a0	;pièce suivante
	dbf	d7,.bcl1
	rts





;-- CONFIGURER LES NORMALES DES POLYGONNES EN ROTATION	
RotCour_INIT_CreerNormalesCouronne:
;test OK

	;-- Creér les normales des 4 faces de la couronne
	;ENTREE:
	;RotCour_Normales_A_Sauver:  dc.w	9,3,3,0,3,3
	;
	;SORTIE:
	;NORMALESCouronnes : 		dc.w 4 * Ni(nx,ny,nz) des 4 couronnes
	;NORMALESCouronnesOffset:	dc.w 0,0,N1-NORMALE,N2-NORMALE,N3-NORMALE,N4-NORMALE
	;
	lea		RotCour_Normales_A_Sauver(pc),a0
	lea		NORMALESCouronnes(pc),a2
	moveq.l	#0,d3
	moveq.l	#0,d2			;index de normale
	move.w	#6-1,d0
.blc:
		move.w	(a0)+,d1	;d1 = nb de fois que la normale est sortie
		;cmp.w	#0,d1		
		;beq		.normaleInchangee
.pas0:
		cmp.w	#9,d1		
		bne		.pasNormaleInchangee
.normaleInchangee:
		;sorti 9 fois = Normale à l'axe de rotation

		;-- NORMALESCouronnesOffset
		lea		NORMALESCouronnesOffset(pc),a3
		move.w	d2,d3		;indexNormale
		add.w	d3,d3		;1 offset = 2 octets
		add.l	d3,a3		;A3=ptr sur table NORMALESCouronnesOffset

		move.w	d2,d3		;indexNormale
		mulu	#6,d3		;1 normale = 6 octets

		move.w	d3,(a3)		;Ptr NORMALES selon index, pas utilisé pas la suite mais bon ... on sait jamais
		
		;-- CREER NormaleCouronneOrientee pour Normale Axe de la couronne
		;créé directement dans table CouronnesOrientees 
		;car la rotation ne change rien à cette normale qui est colinéaire à l'axe de rotattion
		lea		NORMALES(pc),a4		;ptr NORMALES
		move.l	d2,d3		;indexNormale
		mulu	#6,d3		;1 normale = 6 octets
		add.l	d3,a4		;Ptr NORMALES selon index
		lea 	NORMALESCouronnesOrienteesAxeRot(pc),a3
		move.w	(a4)+,(a3)+	;nx
		move.w	(a4)+,(a3)+	;ny
		move.w	(a4)+,(a3)	;nz
		
		bra		.finTest(pc)	
.pasNormaleInchangee:
		cmp.w	#3,d1		
		bne		.finTest
		;sortie 3 fois = normale d'un côté de couronne
		;
		;Enregistrer l'offset NaX-NORMALES
		lea		NORMALESCouronnes(pc),a3
		move.l	a2,a5
		sub.l	a3,a5
		add.w	#NORMALESCouronnesOrientees-NORMALES,a5
		;
		lea		NORMALESCouronnesOffset(pc),a3
		move.w	d2,d3		;indexNormale
		add.w	d3,d3		;1 offset = 2 octets
		add.l	d3,a3		;ptr sur NORMALESCouronnesOffset
		;
		move.w	a5,(a3)		;on enregistre l'offset dans la table NORMALESCouronnesOffset
		;
		;Créer la normale d'un côté de couronne
		lea		NORMALES(pc),a4		;ptr NORMALES
		move.l	d2,d3		;indexNormale
		mulu	#6,d3		;1 normale = 6 octets
		add.l	d3,a4		;Ptr NORMALES selon index
		move.w	(a4)+,(a2)+	;nx
		move.w	(a4)+,(a2)+	;ny
		move.w	(a4)+,(a2)+	;nz
		
.finTest:
		addq.l	#1,d2	;index normale suivant
	dbf		d0,.blc
	rts





RotCour_INIT_CreerTablePtrNormalesCouronneVsPOLYSauve:
	;ENTREE:
	;RotCour_Normales_A_Sauver:  dc.w	9,0,3,3,3,3
	;POLY_SAUVES:	dc.w	ptr POLY, axe i , 0, ...,0
	;
	;SORTIE:
	;TablePtrNormalesCouronneVsPOLYSauve : ptr 1 à 3 de POLYSauve N1, ... , ptr 1 à 3 de POLYSauve N4, ptr 1 à 9 de POLYSauve Axe
	lea		RotCour_Normales_A_Sauver(pc),a0
	
	moveq.l	#0,d2	;index de normale
	moveq.l	#0,d4	;incrément numéro normale côté couronne
	move.w	#6-1,d0
.blc:
		move.w	(a0)+,d1	;nb de fois que la normale est sortie
		;cmp.w	#0,d1		
		;beq		.normaleInchangee
.pas0:
		cmp.w	#9,d1		
		bne		.pasNormaleAxe
.normaleInchangee:
		;9 fois = normale de l'axe
		lea		RotCour_TablePtrNormalesCouronneVsPOLYSauve(pc),a1
		add.l	#4*3*4,a1
		jsr		.CreerPtr
		bra		.finTest(pc)	
.pasNormaleAxe:
		cmp.w	#3,d1		
		bne		.finTest
		;3 fois = normale d'un côté de couronne
		lea		RotCour_TablePtrNormalesCouronneVsPOLYSauve(pc),a1
		add.l	d4,a1
		jsr		.CreerPtr
		add.l	#3*4,d4	;incrément numéro normale côté couronne + 3 ptr.l
.finTest:
		addq.l	#1,d2	;index normale suivant		
	dbf		d0,.blc
		
	rts


.CreerPtr:
	;a1=adresse où ecrire dans la TABLE
	;d2=n° de l'axe à comparer
	lea		POLY_SAUVES(pc),a2
	move.w	#NB_POLY_SAUVE-1,d7
.bcl1:	
		move.w	4(a2),d3	;numero axe de POLYSAuve
		cmp.w	d3,d2		
		bne		.finbcl1
		;l'axe correspond
		move.l	(a2),(a1)+	;on enregistre le ptr de POLYSauve dans table
.finbcl1:
		add.l	#TAILLE_1_POLY_SAUVE,a2	;POLYSauve suivant
	dbf		d7,.bcl1
	rts


RotCour_TablePtrNormalesCouronneVsPOLYSauve:
	;N1
	dcb.l	3,0
	;N2
	dcb.l	3,0
	;N3
	dcb.l	3,0
	;N4
	dcb.l	3,0
	;NAxe
	dcb.l	9,0





RotCour_INIT_CreerPolySauve:
	;TEST OK
	
	;-- dans POLY_SAUVE et dans POLY
	;pour chaque polygone de la couronne
	;changer numNormale par numNORMALESCouronnes 
	;
	;ENTREE:
	;POLY:			dc.w 	offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)	
	;POLY_SAUVES:	dc.w	ptr POLY, axe i , 0, ...,0
	;NORMALESCouronnesOffset:	dc.w 0,0,N1-NORMALE,N2-NORMALE,N3-NORMALE,N4-NORMALE
	;
	;SORTIE:
	;POLY:			dc.w 	Offset Ni-NORMALE, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)	
	;POLY_SAUVES:	dc.w	ptr POLY, Ni-NORMALE , <data POLY.w>
	;
	lea	NORMALESCouronnesOffset(pc),a0
	lea	POLY_SAUVES(pc),a2
	moveq.l	#0,d0
	move.w	#NB_POLY_SAUVE-1,d7
.bcl1:
		;Traiter 1 POLY SAUVE
		move.l	(a2)+,a1	;ptr POLY
		move.w	(a2),d0		;num axe i
		subq.w	#1,d0
		add.b	d0,d0		;*2
		move.w	(a0,d0),d0	;offset Ni-NORMALE=f(Axe i)
		;on enregistre l'offset Ni-NORMALE ...
		move.w	d0,(a1)+	;... dans POLY
		move.w	d0,(a2)+	;... dans POLY_SAUVE 
		;on recopie le reste du POLYnome
		move.w	#((TAILLE_1_POLY-2)/2)-1,d0
.bcl2:
			move.w	(a1)+,(a2)+
		dbf	d0,.bcl2
	dbf	d7,.bcl1
	rts

RotCour_Normales_A_Sauver:
	;aX1,aY1,aZ1,aX2,aY2,aZ2
	;resultat type pour une couronne, nb de normales = 9,3,3,0,3,3
	;dcb.w	6,0	
	dc.w	9,3,3,0,3,3	;exemple si Ax1 axe de rotation
RotCour_Normales_A_Permuter:	



;  ___ 
; | __|
; | _| 
; |___| EXECUTER LA ROTATION EN COURS
;      

;-- si rotation de couronne en cours
;
;-- INCREMENTER ANGLE DE ROTATION
	;--> RotCour_IncrementerAxeRotation()
;
;-- TOURNER LA COURONNE
	;--> RotCour_TournerNormalesCouronne()
	;Tourner les normales des couronnes :
	;NORMALESCouronnesOrientees = rotationCouronne(NORMALESCouronnes, axe)
	;
	;--> RotCour_Orienter3DNormalesCouronne()
	;Orienter en 3D lesNormales des couronnes :
	;nY = rotation3D(NORMALESCouronnesOrientees, aX, aY, aZ)
	;
	;--> RotCour_TournerEtCopierPOLYSauves()
	;pour les nY orientées vers observateur (polygone visible)
	;	POLY = rotationCouronne(POLYSauve, axe)
	;		nota : POLYSauve doit contenir l'adresse de POLY
	;
	;POLY et NORMALES sont alors prêt pour une rotation3D avec la couronne tournée
;
;-- si rotation terminée SEQUENCE SUIVANTE

	
RotCour_TournerCouronne:
	bsr	RotCour_IncrementerAxeRotation
	bsr	RotCour_TournerNormalesCouronne
	bsr	RotCour_Orienter3DNormalesCouronne
	bsr	RotCour_TournerEtCopierPOLYSauves
	bsr	RotCour_TestFinRotation
	rts

RotCour_IncrementerAxeRotation:
	;TEST OK
	;--- incrementer Axe
	lea		RotCour_DATA_ROTATION(pc),a0
	addq.l	#2,a0		;on saute AxeDeRotationEnCours
	move.w	(a0)+,d0	;VitessDeRotation
	move.w	(a0),d1		;ValeurDeRotation
	add.w	d0,d1
	move.w	d1,(A0)		;ValeurDeRotation
	rts
	
	
RotCour_TournerNormalesCouronne:
	;TEST OK
	;tourner les 4 normales selon axe
	;
	;Entree:
	;	NORMALESCouronnes dcb.w	4*3,0 ;4*(nx,ny,nz)
	;Sortie:
	;	NORMALESCouronnesOrientees:	dcb.w	4*3,0	;4*(nx,ny,nz)
	;	nota : ces normales sont les 4 dernières de NORMALES 
	
	
	lea		RotCour_DATA_ROTATION(pc),a5	
	jsr		RotCour_ChargerCosSinSelonAngle(pc)	;A5 = RotCour_DATA_ROTATION(pc) => d5=cos(az)sin(az), A5 = RotCour_DATA_ROTATION(pc)
	
	lea		NORMALESCouronnes(pc),a0
	lea		NORMALESCouronnesOrientees(pc),a1
	move.w	(a5),d4		;RotCour_DATA_AxeRotation
	moveq.l	#4-1,d6		;4 normales de couronnes
	jsr		RotCour_TournerNormalesSelonAngleRot(pc)	;A0 = SOURCE normales, A1 = DEST Normales, d4=axe rot, d5=CosSin, d6 = nb.normales - 1

	rts






RotCour_TournerEtCopierPOLYSauves:
	;Entree:
	;	NORMALESCalculees ... NORMALESCouronnesOrienteesCalculees: dc.w Ny,0,0 ...  Ny2,0,0
	;	POLY_SAUVES:	dc.w	ptr POLY, Ni-NORMALE , <data POLY.w>
	
	;Sortie:
	;	si NORMALESCouronnesOrienteesCalculees visible
	;	POLY:			dc.w 	Ni-NORMALE, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	;


	lea		RotCour_DATA_ROTATION(pc),a5	
	jsr		RotCour_ChargerCosSinSelonAngle(pc)	;A5 = RotCour_DATA_ROTATION(pc) => d5=cos(az)sin(az), A5 = RotCour_DATA_ROTATION(pc)

	
	lea		POLY_SAUVES(pc),a0	;ptr POLY, numero de offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	lea		NORMALESCalculees(pc),a3	;NORMALESCouronnesOrienteesCalculees étant à la suite

		
	;-- pour chaque POLYSAUVE
	; si N visible

	moveq.l	#NB_POLY_SAUVE-1,d7	;21 POLY SAUVE
.bclD7:
		move.w	4(a0),d0	;numero de "normaleY"
		tst.w	(a3,d0)		;test du signe de la "normaleY"
		bpl		.SauteBclD7	;saute si >=0 cad normale orientee vers le fond
		
		;on a une normale visible

		move.l	(a0),a1		;ptr de POLY
		add.l	#4+2+2,a0	;on saute le ptr, la normale et la couleur dans POLYSAUVE
		add.l	#2+2,a1		;on saute la normale et la couleur dans POLY

		move.w	(a5),d4		;RotCour_DATA_AxeRotation //TODO voir comment ne pas appeler 21 fois le test d'axe
		moveq.l	#3-1,d6		;3 points à tourner, le 4eme sera fait par méthodevectorielle
		jsr		RotCour_TournerNormalesSelonAngleRot(pc)	;A0 = SOURCE normales, A1 = DEST Normales, d4=axe rot, d5=CosSin, d6 = nb.points - 1

		add.l	#6,a0		;POLYSauve suivant
	
	dbf		d7,.bclD7
	bra		.finBclD7

.SauteBclD7:
		;on calcule pas
		add.l	#TAILLE_1_POLY_SAUVE,a0	;Polygone suivant
	dbf	d7,.bclD7
	
.finBclD7:	
	rts



RotCour_ChargerCosSinSelonAngle:
	;TEST OK
	;ENTREE : 
	;	A5 = RotCour_DATA_ROTATION(pc)
	;SORTIE :
	;	d5=cos(az)sin(az)
	;	A5 = RotCour_DATA_ROTATION(pc)
	;INTERNE :
	;	d0,d5
	;	a2,a5
	
	;-- Angle de rotation
	moveq.l	#0,d0
	move.w	4(a5),d0	;angle de rotation
	
	move.w	(a5),d5		;axe de rotation
	;-- angle opposé si ax2, ay2 ou az2
	cmp.w	#aX2,d5
	beq		.inv
	cmp.w	#aY2,d5
	beq		.inv
	cmp.w	#aZ2,d5
	bne		.PasInv
.inv:
	move.l	d0,d5	;angle de rotation
	move.w	#360,d0
	sub.w	d5,d0	;angle=360°-angle
.pasInv:

	;-- créer le cos et sin
	lsl.l	#2,d0
	lea		CosSinTbl(pc),a2
   	move.l  (a2,d0),d5  ;cos(aZ) sin(aZ)
	;d5=cos(az)sin(az)
	
	rts



	
	
	
RotCour_TournerNormalesSelonAngleRot:
	;-- Oriente une série de coordonnées
	;
	;ENTREE : 
	;	a0 = adresse SOURCE 1ere normale ou point (nx,ny,nz)
	;	a1 = adresse DEST
	;	d4 = axe de rotation
	;	d6 = nombre de normales - 1
	;	d5 = cos(angleRot)sin(angleRot)
	;SORTIE :
	;	n*d6 Normales orientées dans DEST (a1)
	;INTERNE :
	;	d0,d1,d2,d4,d5,d6
	;	a0,a1
	;

.TestAx:
	cmp.w	#aX1,d4
	beq		.RotAx
	cmp.w	#aX2,d4
	bne		.TestAy
.RotAx:
	;-- Rotation Ax
.bclAx:
	;faire une rotation plan selon Axe
	;si Ax1,Ax2, (nY,Nz)=rotation(Ax1 ou Ax2)
	move.w	(a0)+,d4;X
	move.w	(a0)+,d0;Y
	move.w	(a0)+,d1;Z
	bsr		CalculerXY_1Axe ;(d0=x, d1=y, d5=cos(az)sin(az)) => d2=x1, d1=y1, d5=cos(az)sin(az), d3
	move.w	d4,(a1)+;pas de modif car selon axe
	move.w	d2,(a1)+
	move.w	d1,(a1)+
	dbf		d6,.bclAx
	rts
	
.TestAy:
	cmp.w	#aY1,d4
	beq		.RotAy
	cmp.w	#aY2,d4
	bne		.TestAz
.RotAy:
	;-- Rotation Ay
.bclAy:
	;faire une rotation plan selon Axe
	;si Ay1,Ay2, (nY,Nz)=rotation(Ay1 ou Ay2)
	move.w	(a0)+,d1;X
	move.w	(a0)+,d4;Y pas de modif car selon axe
	move.w	(a0)+,d0;Z
	bsr		CalculerXY_1Axe ;(d0=x, d1=y, d5=cos(az)sin(az)) => d2=x1, d1=y1, d5=cos(az)sin(az), d3
	move.w	d1,(a1)+
	move.w	d4,(a1)+;pas de modif car selon axe
	move.w	d2,(a1)+
	dbf		d6,.bclAy
	rts

.TestAz:
	;si Az1,Az2, (nY,Nz)=rotation(Az1 ou Az2)
	cmp.w	#aZ1,d4
	beq		.RotAz
	cmp.w	#aZ2,d4
	bne		.FinTest
.RotAz:
	;-- Rotation Az
.bclAz:
	;faire une rotation plan selon Axe
	;si Az1,Az2, (nY,Nz)=rotation(Az1 ou Az2)
	move.w	(a0)+,d0;X
	move.w	(a0)+,d1;Y
	move.w	(a0)+,d4;Z pas de modif car selon axe
	bsr		CalculerXY_1Axe ;(d0=x, d1=y, d5=cos(az)sin(az)) => d2=x1, d1=y1, d5=cos(az)sin(az), d3
	move.w	d2,(a1)+
	move.w	d1,(a1)+
	move.w	d4,(a1)+;pas de modif car selon axe
	dbf		d6,.bclAz	
	rts
.FinTest:

	rts

	
	

	




RotCour_Orienter3DNormalesCouronne:
	;Entree:
	;	NORMALESCouronnesOrientees:	dcb.w	4*3,0	;4*(nx,ny,nz)
	;	nota : ces normales sont les 4 dernières de NORMALES ;NORMALESCalculees Ny
	;Sortie:
	;	NORMALESCouronnesOrienteesCalculees: dc.w Ny,0,0 ...  Ny2,0,0
	;	NOTA : reprendre code pour les autres normales

	;--- CALCULER LA TABLE DES NORMALES

	;jsr	RotCour_ChargerTableTrigo	;d3 = cos(aX)sin(aX), d4 = cos(aY)sin(aY), d5 = cos(aZ)sin(aZ), interne A3 .. A6
	
	lea		Angles(pc),a2
	lea		CosSinTbl(pc),a3
	;A4=aX
	move.w	(a2)+,d3
    lsl.w	#2,d3		;aX
    move.l  (a3,d3),d3  ;cos(aX) sin(aX)
	;A5=aY
	move.w	(a2)+,d4
    lsl.w	#2,d4
  	move.l  (a3,d4),d4  ;cos(aY)
	;A6=aZ
	move.w	(a2)+,d5
	lsl.w	#2,d5
	move.l  (a3,d5),d5  ;cos(aZ) sin(aZ)
	
	lea	NORMALESCouronnesOrientees(pc),a0
	lea	NORMALESCouronnesOrienteesCalculees(pc),a1
	move.l	#5-1,d7	;5 normales : 4 côtés + 1 face
.bcl1:
		;--- Calculer la normale du polygone
		move.w	(A0)+,d0	;nx
		move.w	(A0)+,d1	;ny
		move.w	(A0)+,d2	;nz
		bsr     Calculer_Y_Axes_Ax_AZ	;CalculerXYZ_3Axes ;renvoie D0=Y
		move.w	d0,(a1)		;ny2
		addq.l	#6,a1		;le pas est de 3.w
		;bpl		NormaleVersFond(pc)	;saute si d0>=0 cad normale orientee vers le fond
	dbf	d7,.bcl1	
	
	rts







RotCour_TestFinRotation:
	lea		RotCour_DATA_ROTATION(pc),a0
	move.w	4(a0),d1		;ValeurDeRotation
	cmp.w	#90,d1
	beq		.Fin
	cmp.w	#360-90,d1
	bne		.pasFin
.Fin:
	;on est arrivé à la fin de la rotation
	;move.w	#0,(a0)	;axe à 0 = pas de rotation
	jsr		RotCour_SEQ_SUIVANTE(pc)
.pasFin:
	rts
	

;  ___ 
; | __|
; | _| 
; |_| FIN ROTATION DE COURONNE


;	POLY comporte la couronne tournée dans sa position finale
;   il faut maintenant changer les normales dans PIECE et POLY
;
	;dans PIECE
	;pour chaque pièce concernée pas l'axe de rotation
	;changer les axes des 4 faces de le couronne tournée
	;en utilisant TableDePermutationAxes
;
	;dans POLY de PIECE concernée
	;pour chaque polygonne concerné par l'axe de rotation
	;changer le numNORMALES
	;en utilisant TableDePermutationAxes
;-- SEQUENCE STOP


RotCour_FinaliserRotationCouronne:
	bsr		RotCour_Tourner90EtCopierPOLYSauves
	bsr		RotCour_ChangerAxesPiecesCouronne
	bsr		RotCour_MettreAZeroAxe
	jsr		RotCour_SEQ_SUIVANTE(pc)
	rts

RotCour_Tourner90EtCopierPOLYSauves:
	;TODO voir à faire une rotation selon formule plutot que cos et sin :
	;Rot+90(x;y) => (-y; x)
	;Rot-90(x;y) => ( y;-x)
	;
	;Entree:
	;	NORMALESCalculees ... NORMALESCouronnesOrienteesCalculees: dc.w Ny,0,0 ...  Ny2,0,0
	;	POLY_SAUVES:	dc.w	ptr POLY, Ni-NORMALE , <data POLY.w>
	;Sortie:
	;	pour chaque POLY
	;	POLY:			dc.w 	Ni-NORMALE, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	;

	lea		RotCour_DATA_ROTATION(pc),a5	
	jsr		RotCour_ChargerCosSinSelonAngle(pc)	;A5 = RotCour_DATA_ROTATION(pc) => d5=cos(az)sin(az), A5 = RotCour_DATA_ROTATION(pc)

	lea		POLY_SAUVES(pc),a0	;ptr POLY, numero de offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	lea		NORMALESCalculees(pc),a3	;NORMALESCouronnesOrienteesCalculees étant à la suite
	
	;-- pour chaque POLYSAUVE
	moveq.l	#NB_POLY_SAUVE-1,d7	;21 POLY SAUVE
.bclD7:
		move.l	(a0),a1		;ptr de POLY
		add.l	#4+2+2,a0	;on saute le ptr, la normale et la couleur dans POLYSAUVE
		add.l	#2+2,a1		;on saute la normale et la couleur dans POLY

		move.w	(a5),d4		;RotCour_DATA_AxeRotation //TODO voir comment ne pas appeler 21 fois le test d'axe
		moveq.l	#3-1,d6		;3 points à tourner, le 4eme sera fait par méthodevectorielle
		
		;TODO comprendre pourquoi rotation 90 à des défauts
		;jsr		RotCour_TournerNormalesSelonAngleRot(pc)	;A0 = SOURCE normales, A1 = DEST Normales, d4=axe rot, d5=CosSin, d6 = nb.points - 1
		jsr	 	RotCour_TournerCoordsSelonAngle90(pc)
		
		add.l	#6,a0		;POLYSauve suivant	
	dbf		d7,.bclD7	
	rts








RotCour_TournerCoordsSelonAngle90:
	;-- Oriente une série de coordonnées
	;
	;ENTREE : 
	;	a0 = adresse SOURCE 1ere normale ou point (nx,ny,nz)
	;	a1 = adresse DEST
	;	d4 = axe de rotation
	;	d6 = nombre de normales - 1
	;	d5 = cos(angleRot)sin(angleRot)
	;SORTIE :
	;	n*d6 Normales orientées dans DEST (a1)
	;INTERNE :
	;	d0,d1,d2,d4,d5,d6
	;	a0,a1
	;
	move.w	RotCour_DATA_VitessDeRotation(pc),d5
	
.TestAx:
	cmp.w	#aX1,d4
	beq		.RotAx
	cmp.w	#aX2,d4
	bne		.TestAy
	neg.w	d5	;on inverse le sens
	
.RotAx:
	;-- Rotation Ax
.bclAx:
	;faire une rotation plan selon Axe
	;si Ax1,Ax2, (nY,Nz)=rotation(Ax1 ou Ax2)
	move.w	(a0)+,d4;X
	move.w	(a0)+,d0;Y
	move.w	(a0)+,d1;Z
	tst.w	d5
	bpl		.bclAx1	;saute si positif
	;Rot-90(y;z) => ( z;-y)
	neg.w	d0
	bra		.bclAx2
.bclAx1:
	;Rot+90(y,z) => (-z; y)
	neg.w	d1
.bclAx2:	
	move.w	d4,(a1)+;pas de modif car selon axe
	move.w	d1,(a1)+
	move.w	d0,(a1)+
	dbf		d6,.bclAx
	rts
	
.TestAy:
	cmp.w	#aY1,d4
	beq		.RotAy
	cmp.w	#aY2,d4
	bne		.TestAz
	neg.w	d5	;on inverse le sens
	
.RotAy:
	;-- Rotation Ay
.bclAy:
	;faire une rotation plan selon Axe
	;si Ay1,Ay2, (nY,Nz)=rotation(Ay1 ou Ay2)
	move.w	(a0)+,d1;X
	move.w	(a0)+,d4;Y pas de modif car selon axe
	move.w	(a0)+,d0;Z
	tst.w	d5
	bpl		.bclAy1	;positif
	;Rot-90(z;x) => ( x;-z)
	neg.w	d0
	bra		.bclAy2
.bclAy1:
	;Rot+90(z;x) => (-x; z)
	neg.w	d1
.bclAy2:	
	move.w	d0,(a1)+
	move.w	d4,(a1)+;pas de modif car selon axe
	move.w	d1,(a1)+
	dbf		d6,.bclAy
	rts

.TestAz:
	;si Az1,Az2, (nY,Nz)=rotation(Az1 ou Az2)
	cmp.w	#aZ1,d4
	beq		.RotAz
	cmp.w	#aZ2,d4
	bne		.FinTest
	neg.w	d5	;on inverse le sens
.RotAz:
	;-- Rotation Az
.bclAz:
	;faire une rotation plan selon Axe
	;si Az1,Az2, (nY,Nz)=rotation(Az1 ou Az2)
	move.w	(a0)+,d0;X
	move.w	(a0)+,d1;Y
	move.w	(a0)+,d4;Z pas de modif car selon axe
	tst.w	d5
	bpl		.bclAz1	;positif
	;Rot-90(x;y) => ( y;-x)
	neg.w	d0
	bra		.bclAz2
.bclAz1:
	;Rot+90(x;y) => (-y; x)
	neg.w	d1
.bclAz2:
	move.w	d1,(a1)+
	move.w	d0,(a1)+
	move.w	d4,(a1)+;pas de modif car selon axe
	dbf		d6,.bclAz	
	rts
.FinTest:

	rts





RotCour_ChangerAxesPiecesCouronne:
	;dans PIECE
	
	;ENTREE:
	;	PIECE: 	dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, aX2,aY2,aZ2
	;	POLY: 	dc.w    NaX2-Normales, 3, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
	;					numero de offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	
	;SORTIE:
	;	PIECE: dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, NewAxe1,..,NewAxe3
	;	POLY: 	dc.w    NaX2-Normales, 3, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
	;					numero de offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	;
	;pour chaque pièce concernée pas l'axe de rotation
	;changer les axes des 4 faces de le couronne tournée
	;en utilisant TableDePermutationAxes

	;-- Definir adresse de table de permutation
	move.w	RotCour_DATA_AxeRotation,d0	;axe de rotation
	move.w	RotCour_DATA_VitessDeRotation,d1
	
.testAx:
	cmp.w	#aX1,d0
	beq		.axeAx
	cmp.w	#aX2,d0
	bne		.testAy
	neg.w	d1		;on inverse le sens de rotation
.axeAx:
	;Axe Ax
	lea		aXiP(pc),a4
	bra		.finTest
.testAy:

	cmp.w	#aY1,d0
	beq		.axeAy
	cmp.w	#aY2,d0
	bne		.testAz
	neg.w	d1		;on inverse le sens de rotation
.axeAy:
	;Axe Ay
	lea		aYiP(pc),a4
	bra		.finTest
.testAz:

	cmp.w	#aZ1,d0
	beq		.axeAz
	cmp.w	#aZ2,d0
	bne		.fintest
	neg.w	d1		;on inverse le sens de rotation
.axeAz:
	;Axe Az
	lea		aZiP(pc),a4
.finTest:
	
	tst.w	d1
	bpl		.finSens	;saute si >=0
	add.l	#7*2,a4	;on prend 2eme ligne de permutation
.finSens		
		
		
		
	;
	move.w	RotCour_DATA_AxeRotation,d0	;axe de rotation
	lea		PIECE(pc),a0
	lea		POLY(pc),a2
	move.w	#NB_PIECE-1,d7	;26 pièces
	;PIECE:	dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, aX2,aY2,aZ2
.bclPIECE:
		move.l	a0,a3			;ptr PIECE
		move.w	(a3),d1			;nb de Poly de la pièce
		sub.w	#1,d1			;init compteur POLY
		add.l	#4*2,a3			;ptr PIECE.1erAxe
.bclPOLY:
			move.w	(a3)+,d2	;PIECE.axe
			cmp.w	d2,d0		;PIECE.axe = AxeRotation ?
			bne		.POLYSuivant
			;PIECE.axe = AxeRotation
			;l'axe est présent, la pièce est concernée
			
			;RotCour_DATA_VitessDeRotation:	dc.w	0

	
			move.l	a0,a3		;PIECE.ptr	
			move.w	(a3)+,d2	;PIECE.nbPOLY
			sub.w	#1,d2
.bclTraitePOLYetAXE:
				;-- Traitement de l'Axe
				moveq.l	#0,d4
				move.w	6(a3),d4	;Axe.old
				add.w	d4,d4		;offset .w
				move.w	(a4,d4),d4	;Axe.new
				move.w	d4,6(a3)

				;-- Traitement du POLY
				lea		POLY(pc),a1	;Adresse POLY:
				moveq.l	#0,d3	
				move.w	(a3)+,d3	;ofsset Pxxx-POLY
				add.l	d3,a1		;POLY.ptr à changer
				
				;(a1)=(Axe.new-1)*6
				;NORMALES:
				;NaX1:	dc.w    50,0,0
				sub.w	#1,d4
				mulu	#6,d4
				move.w	d4,(a1)

			dbf		d2,.bclTraitePOLYetAXE	;poly Suivant
			bra		.PIECESuivante

.POLYSuivant:
		dbf	d1,.bclPOLY		;POLY suivant
.PIECESuivante:
		add.l	#TAILLE_1_PIECE,a0	;pièce suivante
	dbf	d7,.bclPIECE
	rts


;-- TABLE DE PERMUTATION
;				0,aX1,aY1,aZ1,aX2,aY2,aZ2
TableDePermutationAxes: 
;ROT	dc.w	Devient
aXiP:	dc.w	0,aX1,aZ1,aY2,aX2,aZ2,aY1
aXin:	dc.w	0,aX1,aZ2,aY1,aX2,aZ1,aY2
aYiP:	dc.w	0,aZ2,aY1,aX1,aZ1,aY2,aX2
aYin:	dc.w	0,aZ1,aY1,aX2,aZ2,aY2,aX1
aZiP:	dc.w	0,aY1,aX2,aZ1,aY2,aX1,aZ2
aZin:	dc.w	0,aY2,aX1,aZ1,aY1,aX2,aZ2





RotCour_MettreAZeroAxe:
	lea		RotCour_DATA_ROTATION(pc),a0
	move.w	#0,(a0)	;axe à 0 = plus de rotation, peut être pas utile
	rts








;  ___    ___   ___     ___          _      _   _        
; |   \  | __| | __|   | _ \  _  _  | |__  (_) | |__  ___
; | |) | | _|  | _|    |   / | || | | '_ \ | | | / / (_-<
; |___/  |___| |_|     |_|_\  \_,_| |_.__/ |_| |_\_\ /__/
;       ____________
;      /   /   /   /|                        /|\Z  _ Y
;     /___/___/___/ |                         |    /|
;    /   /   /   /| |                        aZ1  /
;   /___/___/___/ |/|                         |  aY1
;  /   /   /   /| | |                         | /
; /___/___/___/ |/|/|                         |/
; |   |   |   | | | |                aX2 -----|---- aX1 ----> X
; |___|___|___|/|/|/                         /|
; |   |   |   | ||/                         / |
; |___|___|___|/|/                     aY2 /  |
; |   |   |   | /                            aZ2
; |___|___|___|/
;  


;
;-- AXES DE ROTATION
;NumAxeRot=n, aX1=1, aY1=2, aZ1=3, aX2=4, aY2=5, aZ2=6
aX1=1
aY1=2
aZ1=3
aX2=4
aY2=5
aZ2=6


;
;-- PIECES
;
;.type (1 centre, 2 bord, 3 coin)=.nbPolygones, .polygone_1, .polygone_2, .polygone_3, .axeDeRotation_1, .axeDeRotation_2, .axeDeRotation_3
NB_PIECE=26
PIECE:
PCE111: dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, 	aX2,aY2,aZ2
PCE211: dc.w    2,P211aY2-POLY,P211aZ2-POLY,0, 				aY2,aZ2,0
PCE311: dc.w    3,P311aX1-POLY,P311aY2-POLY,P311aZ2-POLY, 	aX1,aY2,aZ2
PCE121: dc.w    2,P121aX2-POLY,P121aZ2-POLY,0, 				aX2,aZ2,0
PCE221: dc.w    1,P221aZ2-POLY,0,0, 						aZ2,0,0
PCE321: dc.w    2,P321aX1-POLY,P321aZ2-POLY,0, 				aX1,aZ2,0
PCE131: dc.w    3,P131aX2-POLY,P131aY1-POLY,P131aZ2-POLY, 	aX2,aY1,aZ2
PCE231: dc.w    2,P231aY1-POLY,P231aZ2-POLY,0, 				aY1,aZ2,0
PCE331: dc.w    3,P331aX1-POLY,P331aY1-POLY,P331aZ2-POLY, 	aX1,aY1,aZ2
PCE112: dc.w    2,P112aX2-POLY,P112aY2-POLY,0, 				aX2,aY2,0
PCE212: dc.w    1,P212aY2-POLY,0,0, 						aY2,0,0
PCE312: dc.w    2,P312aX1-POLY,P312aY2-POLY,0,				aX1,aY2,0
PCE122: dc.w    1,P122aX2-POLY,0,0, 						aX2,0,0
PCE322: dc.w    1,P322aX1-POLY,0,0, 						aX1,0,0
PCE132: dc.w    2,P132aX2-POLY,P132aY1-POLY,0, 				aX2,aY1,0
PCE232: dc.w    1,P232aY1-POLY,0,0, 						aY1,0,0
PCE332: dc.w    2,P332aX1-POLY,P332aY1-POLY,0, 				aX1,aY1,0
PCE113: dc.w    3,P113aX2-POLY,P113aY2-POLY,P113aZ1-POLY, 	aX2,aY2,aZ1
PCE213: dc.w    2,P213aY2-POLY,P213aZ1-POLY,0, 				aY2,aZ1,0
PCE313: dc.w    3,P313aX1-POLY,P313aY2-POLY,P313aZ1-POLY, 	aX1,aY2,aZ1
PCE123: dc.w    2,P123aX2-POLY,P123aZ1-POLY,0, 				aX2,aZ1,0
PCE223: dc.w    1,P223aZ1-POLY,0,0, 						aZ1,0,0
PCE323: dc.w    2,P323aX1-POLY,P323aZ1-POLY,0, 				aX1,aZ1,0
PCE133: dc.w    3,P133aX2-POLY,P133aY1-POLY,P133aZ1-POLY, 	aX2,aY1,aZ1
PCE233: dc.w    2,P233aY1-POLY,P233aZ1-POLY,0, 				aY1,aZ1,0
PCE333: dc.w    3,P333aX1-POLY,P333aY1-POLY,P333aZ1-POLY, 	aX1,aY1,aZ1
FIN_PIECE:
TAILLE_1_PIECE=(FIN_PIECE-PIECE)/NB_PIECE


;
;-- POLYGINES
;
;numero de offset normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
NB_POLY=54
POLY:

P111aX2:    dc.w    NaX2-Normales, 3, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
P121aX2:    dc.w    NaX2-Normales, 3, -53,-16,-50, -53,16,-50, -53,16,-18, -53,-16,-18
P131aX2:    dc.w    NaX2-Normales, 3, -53,18,-50, -53,50,-50, -53,50,-18, -53,18,-18
P112aX2:    dc.w    NaX2-Normales, 3, -53,-50,-16, -53,-18,-16, -53,-18,16, -53,-50,16
P122aX2:    dc.w    NaX2-Normales, 3, -53,-16,-16, -53,16,-16, -53,16,16, -53,-16,16
P132aX2:    dc.w    NaX2-Normales, 3, -53,18,-16, -53,50,-16, -53,50,16, -53,18,16
P113aX2:    dc.w    NaX2-Normales, 3, -53,-50,18, -53,-18,18, -53,-18,50, -53,-50,50
P123aX2:    dc.w    NaX2-Normales, 3, -53,-16,18, -53,16,18, -53,16,50, -53,-16,50
P133aX2:    dc.w    NaX2-Normales, 3, -53,18,18, -53,50,18, -53,50,50, -53,18,50

P111aY2:    dc.w    NaY2-Normales, 2, -50,-53,-50, -18,-53,-50, -18,-53,-18, -50,-53,-18
P211aY2:    dc.w    NaY2-Normales, 2, -16,-53,-50, 16,-53,-50, 16,-53,-18, -16,-53,-18
P311aY2:    dc.w    NaY2-Normales, 2, 18,-53,-50, 50,-53,-50, 50,-53,-18, 18,-53,-18
P112aY2:    dc.w    NaY2-Normales, 2, -50,-53,-16, -18,-53,-16, -18,-53,16, -50,-53,16
P212aY2:    dc.w    NaY2-Normales, 2, -16,-53,-16, 16,-53,-16, 16,-53,16, -16,-53,16
P312aY2:    dc.w    NaY2-Normales, 2, 18,-53,-16, 50,-53,-16, 50,-53,16, 18,-53,16
P113aY2:    dc.w    NaY2-Normales, 2, -50,-53,18, -18,-53,18, -18,-53,50, -50,-53,50
P213aY2:    dc.w    NaY2-Normales, 2, -16,-53,18, 16,-53,18, 16,-53,50, -16,-53,50
P313aY2:    dc.w    NaY2-Normales, 2, 18,-53,18, 50,-53,18, 50,-53,50, 18,-53,50

P111aZ2:    dc.w    NaZ2-Normales, 6, -50,-50,-53, -18,-50,-53, -18,-18,-53, -50,-18,-53
P211aZ2:    dc.w    NaZ2-Normales, 6, -16,-50,-53, 16,-50,-53, 16,-18,-53, -16,-18,-53
P311aZ2:    dc.w    NaZ2-Normales, 6, 18,-50,-53, 50,-50,-53, 50,-18,-53, 18,-18,-53
P121aZ2:    dc.w    NaZ2-Normales, 6, -50,-16,-53, -18,-16,-53, -18,16,-53, -50,16,-53
P221aZ2:    dc.w    NaZ2-Normales, 6, -16,-16,-53, 16,-16,-53, 16,16,-53, -16,16,-53
P321aZ2:    dc.w    NaZ2-Normales, 6, 18,-16,-53, 50,-16,-53, 50,16,-53, 18,16,-53
P131aZ2:    dc.w    NaZ2-Normales, 6, -50,18,-53, -18,18,-53, -18,50,-53, -50,50,-53
P231aZ2:    dc.w    NaZ2-Normales, 6, -16,18,-53, 16,18,-53, 16,50,-53, -16,50,-53
P331aZ2:    dc.w    NaZ2-Normales, 6, 18,18,-53, 50,18,-53, 50,50,-53, 18,50,-53

P311aX1:    dc.w    NaX1-Normales, 1, 53,-50,-50, 53,-18,-50, 53,-18,-18, 53,-50,-18
P321aX1:    dc.w    NaX1-Normales, 1, 53,-16,-50, 53,16,-50, 53,16,-18, 53,-16,-18
P331aX1:    dc.w    NaX1-Normales, 1, 53,18,-50, 53,50,-50, 53,50,-18, 53,18,-18
P312aX1:    dc.w    NaX1-Normales, 1, 53,-50,-16, 53,-18,-16, 53,-18,16, 53,-50,16
P322aX1:    dc.w    NaX1-Normales, 1, 53,-16,-16, 53,16,-16, 53,16,16, 53,-16,16
P332aX1:    dc.w    NaX1-Normales, 1, 53,18,-16, 53,50,-16, 53,50,16, 53,18,16
P313aX1:    dc.w    NaX1-Normales, 1, 53,-50,18, 53,-18,18, 53,-18,50, 53,-50,50
P323aX1:    dc.w    NaX1-Normales, 1, 53,-16,18, 53,16,18, 53,16,50, 53,-16,50
P333aX1:    dc.w    NaX1-Normales, 1, 53,18,18, 53,50,18, 53,50,50, 53,18,50

P131aY1:    dc.w    NaY1-Normales, 4, -50,53,-50, -18,53,-50, -18,53,-18, -50,53,-18
P231aY1:    dc.w    NaY1-Normales, 4, -16,53,-50, 16,53,-50, 16,53,-18, -16,53,-18
P331aY1:    dc.w    NaY1-Normales, 4, 18,53,-50, 50,53,-50, 50,53,-18, 18,53,-18
P132aY1:    dc.w    NaY1-Normales, 4, -50,53,-16, -18,53,-16, -18,53,16, -50,53,16
P232aY1:    dc.w    NaY1-Normales, 4, -16,53,-16, 16,53,-16, 16,53,16, -16,53,16
P332aY1:    dc.w    NaY1-Normales, 4, 18,53,-16, 50,53,-16, 50,53,16, 18,53,16
P133aY1:    dc.w    NaY1-Normales, 4, -50,53,18, -18,53,18, -18,53,50, -50,53,50
P233aY1:    dc.w    NaY1-Normales, 4, -16,53,18, 16,53,18, 16,53,50, -16,53,50
P333aY1:    dc.w    NaY1-Normales, 4, 18,53,18, 50,53,18, 50,53,50, 18,53,50

P113aZ1:    dc.w    NaZ1-Normales, 5, -50,-50,53, -18,-50,53, -18,-18,53, -50,-18,53
P213aZ1:    dc.w    NaZ1-Normales, 5, -16,-50,53, 16,-50,53, 16,-18,53, -16,-18,53
P313aZ1:    dc.w    NaZ1-Normales, 5, 18,-50,53, 50,-50,53, 50,-18,53, 18,-18,53
P123aZ1:    dc.w    NaZ1-Normales, 5, -50,-16,53, -18,-16,53, -18,16,53, -50,16,53
P223aZ1:    dc.w    NaZ1-Normales, 5, -16,-16,53, 16,-16,53, 16,16,53, -16,16,53
P323aZ1:    dc.w    NaZ1-Normales, 5, 18,-16,53, 50,-16,53, 50,16,53, 18,16,53
P133aZ1:    dc.w    NaZ1-Normales, 5, -50,18,53, -18,18,53, -18,50,53, -50,50,53
P233aZ1:    dc.w    NaZ1-Normales, 5, -16,18,53, 16,18,53, 16,50,53, -16,50,53
P333aZ1:    dc.w    NaZ1-Normales, 5, 18,18,53, 50,18,53, 50,50,53, 18,50,53

FIN_POLY:
TAILLE_1_POLY=(FIN_POLY-POLY)/NB_POLY







; 54 Polygones calculés suite rotation aX, aY, aZ
NB_POLY_CALCULES:	dc.w	0
POLYCALCULES:
;normaleY, coul(1..6), A(x,y,z), B(x,y,z), C(x,y,z), D(x,y,z)
	dcb.b	FIN_POLY-POLY,$12
	dc.w	0	;fin
	
	


NORMALESCouronnesOffset:
	;position des normales type offset NaX-NORMALES
	;en fonction du numéro de la normales 0..5 (ou Ax1..Az2)
	;offset=indexNormale*6+(NORMALESCouronnesOrientees-NORMALES)
	;index  | 0  | 1  | 2  | 3  | 4  | 5  |
	;offset |    | o1 | o2 | o3 |    | o4 |
	;cette table permet de changer les num normales
	;des 4 faces latérales de la couronne en rotation dans POLY et POLYSAUVE
	dcb.w	6,0

NORMALESCouronnes:
	;Normales des 4 faces latérales de la couronne en rotation
	;Ces normales subissent une rotation 
	;pour être enregistrées dans NORMALESCouronnesOrientees
	;dcb.w	4*3,0
	dc.w	$10,$0,$0
	dc.w	$11,$21,$31
	dc.w	$12,$22,$32
	dc.w	$13,$23,$33
	dc.l	$C0FFEE


NORMALES:
NaX1:	dc.w    50,0,0
NaY1:	dc.w    0,50,0
NaZ1:	dc.w    0,0,50
NaX2:	dc.w    -50,0,0
NaY2:	dc.w    0,-50,0
NaZ2:	dc.w    0,0,-50
NORMALESCouronnesOrientees:
		dcb.w	4*3,0	;4*(nx,ny,nz) normales des 4 couronnes
NORMALESCouronnesOrienteesAxeRot:
		dcb.w	1*3,0	;1*(normale de l'axe de rotation)
FIN_NORMALES:
	dc.l	$C0FFEE


NORMALESCalculees:
	dcb.b	NORMALESCouronnesOrientees-NORMALES,$34
NORMALESCouronnesOrienteesCalculees:
	dcb.b	FIN_NORMALES-NORMALESCouronnesOrientees,$56
	dc.w	0 ;fin de normales


;21 Polygones a sauver pour la rotation de couronne
NB_POLY_SAUVE=21
POLY_SAUVES:
	dcb.l	NB_POLY_SAUVE*1			;adresse POLY
	dcb.w	NB_POLY_SAUVE*14,$0AF0	;copie de POLY
FIN_POLY_SAUVES:
TAILLE_1_POLY_SAUVE = (FIN_POLY_SAUVES-POLY_SAUVES)/NB_POLY_SAUVE


FinPROG:
	dc.l	$C0FFEE





	section	coplist,data_c

;   ___                                   _      _        _   
;  / __|  ___   _ __   _ __   ___   _ _  | |    (_)  ___ | |_ 
; | (__  / _ \ | '_ \ | '_ \ / -_) | '_| | |__  | | (_-< |  _|
;  \___| \___/ | .__/ | .__/ \___| |_|   |____| |_| /__/  \__|
;              |_|    |_|                                     
; Copper List

CopListDataStart:
	;Compatibilité ECS avec AGA
	dc.w	$106,$c00	; bplcon3
	dc.w	FMODE,0
	dc.w	$10c,$11	; bplcon4
	;Configuration de l'écran
	;dc.w	DIWSTRT,$2c81,DIWSTOP,$2cc1
	;dc.w	DDFSTRT,$38,DDFSTOP,$d0
	; & = AND, ! = OR , ~ = EOR
	dc.w DIWSTRT,(DISPLAY_Y<<8)!DISPLAY_X ;$2c81	
	dc.w DIWSTOP,((DISPLAY_Y+DISPLAY_DY-256)<<8)!(DISPLAY_X+DISPLAY_DX-256) ;$2cc1
	dc.w DDFSTRT,((DISPLAY_X-17)>>1)&$00FC	;$0038
	dc.w DDFSTOP,((DISPLAY_X-17+(((DISPLAY_DX>>4)-1)<<4))>>1)&$00FC	;$00d0
	;Ce qui revient ((DISPLAY_X-17+DISPLAY_DX-16)>>1)&$00FC si DISPLAY_DX est multiple de 16
	
	dc.w BPLCON0,(DISPLAY_DEPTH<<12)!$0200
	dc.w BPLCON1,SHADOW_DX<<4	;PF2H=Playfield 2 horizontal scroll code
	dc.w BPLCON2,0
	dc.w BPL1MOD,0
	dc.w BPL2MOD,0

;Adresse des bitplanes

CplBitPlanes:
	dc.w BPL1PTL,0,BPL1PTH,0
	dc.w BPL2PTL,0,BPL2PTH,0
	dc.w BPL3PTL,0,BPL3PTH,0

;Couleurs

	IFNE DEBUGDISPLAY_RASTER
	dc.w COLOR08,0		;pas utilisée, pour neutraliser de manière quelconque la modification de COLOR00...
	ELSE
	dc.w COLOR00,0
	ENDC
	dc.w COLOR01,$FFF	;SCROLL_COLOR
	dc.w COLOR02,$F00	;rouge ;SHADOW_COLOR
	dc.w COLOR03,$0F0	;Vert
	dc.w COLOR04,$00F	;bleu
	dc.w COLOR05,$F0F	;
	dc.w COLOR06,$FF0
	dc.w COLOR07,$0FF
	
;Compatibilité ECS avec AGA

	;dc.w FMODE,$0000
	
;Ombre

	dc.w	((DISPLAY_Y+SCROLL_Y+SHADOW_DY-1)<<8)!$0001,$FF00
	dc.w	BPL2MOD,-SHADOW_DY*(DISPLAY_DX>>3)

	dc.w	((DISPLAY_Y+SCROLL_Y+SHADOW_DY)<<8)!$0001,$FF00
	dc.w	BPL2MOD,0
	dc.w	BPLCON1,SHADOW_DX<<4
;miroir
	dc.w	((DISPLAY_Y+MIRROR_Y-1)<<8)!$0001,$FF00
	dc.w	BPL1MOD,-(DISPLAY_DX>>3)
	dc.w	BPL2MOD,(SHADOW_DY-1)*(DISPLAY_DX>>3)

	dc.w	((DISPLAY_Y+MIRROR_Y)<<8)!$0001,$FF00
	dc.w	BPLCON1,$0000
	dc.w	BPL1MOD,-(DISPLAY_DX>>2)
	dc.w	BPL2MOD,-(DISPLAY_DX>>2)
	
	IFNE	DEBUGDISPLAY_RASTER
	dc.w	COLOR08,MIRROR_COLOR	;COLOR08 pas utilisée, pour neutraliser de manière quelconque la modification de COLOR00...
	ELSE
	dc.w	COLOR00,MIRROR_COLOR
	ENDC

	dc.w	COLOR01,MIRROR_SCROLL_COLOR
	dc.w	COLOR02,MIRROR_SCROLL_COLOR
	dc.w	COLOR03,MIRROR_SCROLL_COLOR
	dc.w	COLOR04,MIRROR_SCROLL_COLOR
	dc.w	COLOR05,MIRROR_SCROLL_COLOR
	dc.w	COLOR06,MIRROR_SCROLL_COLOR
	dc.w	COLOR07,MIRROR_SCROLL_COLOR

	dc.w	$ffdf,$fffe 
	dc.w	$2c0f,$fffe,$100,0
;Fin
	dc.l 	-2
	dc.l	-2

; CopListDataEnd:

; COPSIZE=CopListDataEnd-CopListDataStart
; TAILLE_MEM_RESERVEE=COPSIZE+(3*DISPLAY_DEPTH*TAILLE_BITPLANE)




;Bitplanes

	section	screen,bss_c

ScreenA	ds.b	DISPLAY_DEPTH*TAILLE_BITPLANE
ScreenB	ds.b	DISPLAY_DEPTH*TAILLE_BITPLANE
ScreenC	ds.b	DISPLAY_DEPTH*TAILLE_BITPLANE
