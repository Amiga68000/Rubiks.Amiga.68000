;Programme Arnaud.68000 - 2020-11
;Rotation objets filaire 3D
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
;
;

	SECTION Arn,CODE_C


DEBUGDISPLAYTIME=1	;affiche le debug
BLITTER=1		;Tracer pour le scroll au 0=CPU 1=Blitter, non fonctionnel pour le moment
EffacerBitPlaneCache=1
CTR=1		;permet de compter le nombre de boucle d'attente du blitter

AffTexteFixe=1
AffScroll=0	;affiche le scrolling de texte
AffLigneBlitter=1	;affiche le tracé des lignes au blitter

;Objet 3D
Calculer3D=1
AffObjet3D=1

;Angles au depart
InitAngleAx=20
InitAngleAy=35
InitAngleAz=10
;Incrément des axes
PasAngleAX=7
PasAngleAY=1
PasAngleAZ=0
;position du centre objet
offsetX=160	;min 87, maxi 232
offsetZ=100	;mini 87, maxi 168  87=sqr(50^2+50^2+50^2) coin max (50,50,50)

;---------- RUBIK
NBPOLY=54


;Registres

VPOSR=$004
VHPOSR=$006
INTENA=$09A
INTENAR=$01C
INTREQ=$09C
INTREQR=$01E
DMACON=$096
DMACONR=$002
BLTAFWM=$044
BLTALWM=$046
BLTAPTH=$050
BLTAPTL=$052
BLTCPTH=$048
BLTDPTH=$054
BLTAMOD=$064
BLTBMOD=$062
BLTCMOD=$060
BLTDMOD=$066
BLTADAT=$074
BLTBDAT=$072
BLTCON0=$040
BLTCON1=$042
BLTSIZE=$058
DIWSTRT=$08E
DIWSTOP=$090
BPLCON0=$100
BPLCON1=$102
BPLCON2=$104
DDFSTRT=$092
DDFSTOP=$094
BPL1MOD=$108
BPL2MOD=$10A
BPL1PTH=$0E0
BPL1PTL=$0E2
BPL2PTH=$0E4
BPL2PTL=$0E6
BPL3PTH=$0E8
BPL3PTL=$0EA
COLOR00=$180
COLOR01=$182
COLOR02=$184
COLOR03=$186
COLOR04=$188
COLOR05=$18A
COLOR06=$18C
COLOR07=$18E
COP1LCH=$080
COPJMP1=$088
FMODE=$1FC

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
SHADOW_DX=2	;Compris entre 0 et 15
SHADOW_DY=2
SHADOW_COLOR=$0777

TAILLE_BITPLANE=((DISPLAY_DX*DISPLAY_DY)>>3)

SCROLL_POS_Y=162
SCROLL_SPEED=1

;COPSIZE=18*4+14*4+4

;---------- Macros ----------

;Attendre le Blitter. Quand la seconde opérande est une adresse, BTST ne permet de tester que les bits 7-0 de l'octet pointé, mais traitant la première opérande comme le numéro du bit modulo 8, BTST #14,DMACONR(a5) revient à tester le bit 14%8=6 de l'octet de poids fort de DMACONR, ce qui correspond bien à BBUSY...
	
WAITBLIT:	MACRO
_waitBlitter0\@
	IFNE CTR
	add.l	#1,BltCTR
	ENDC
	btst #14,DMACONR(a5)
	bne _waitBlitter0\@
_waitBlitter1\@
	IFNE CTR
	add.l	#1,BltCTR
	ENDC
	btst #14,DMACONR(a5)
	bne _waitBlitter1\@
	IFNE CTR
	sub.l	#2,BltCTR
	ENDC
	ENDM

;Contrôle de l'intégrité du texte afficher. 
;Attention au contexte dans lequel la macro est utilisée, 
;car elle peut modifier la longueur du texte initial 
;(qui doit être au moins aussi long que "You are a LAMER!" 
;sous peine d'écraser des données) 
;et donc embrouiller le code qui était en train de le parcourir




;bra Calcul3D


;---------- Initialisations ----------

;Empiler les registres

	movem.l d0-d7/a0-a6,-(sp) *** NIV1



;Allouer de la mémoire en CHIP mise à 0 pour la Copper list
	
	move.l #COPSIZE,d0
	move.l #$10002,d1
	movea.l $4,a6
	jsr -198(a6)
	move.l d0,copperlist_PTR
	;calcul du pointeur BitPlanes de la copperList
	add.l	#CplBitPlanes-CopListDataStart,d0
	move.l	d0,Copperlist_BitPlanes_PTR
	
;Allouer de la mémoire en CHIP mise à 0 pour les bitplanes

	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	move.l #$10002,d1
	movea.l $4,a6
	jsr -198(a6)
	move.l d0,bitplaneA

	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	move.l #$10002,d1
	movea.l $4,a6
	jsr -198(a6)
	move.l d0,bitplaneB

	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	move.l #$10002,d1
	movea.l $4,a6
	jsr -198(a6)
	move.l d0,bitplaneC

;Idem pour la police de caractères

	move.l #256<<5,d0
	move.l #$10002,d1
	movea.l $4,a6
	jsr -198(a6)
	move.l d0,Font16_PTR

;Couper le système

	movea.l $4,a6
	jsr -132(a6)

;Couper le hardware

	lea $dff000,a5
	move.w INTENAR(a5),intena_PTR
	move.w #$7FFF,INTENA(a5)
	move.w INTREQR(a5),intreq_PTR
	move.w #$7FFF,INTREQ(a5)
	move.w DMACONR(a5),dmacon_PTR
	move.w #$07FF,DMACON(a5)


;---------- Création et activation de la Copper list ----------


RecopierAdresseBplVersCpl:
	;copie les adresses des 3 premiers bitplanes dans copperlist
	moveq	#3-1,d1
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

	;transferer la copperlist en Chip
	move.l	#COPSIZE/4-1,d0
	move.l	#CopListDataStart,a0
	move.l	copperlist_PTR,a1
.l2:
	move.l	(a0)+,(a1)+
	dbf		d0,.l2
	
	;Activer la Copper list
	move.l copperlist_PTR,COP1LCH(a5)
	clr.w COPJMP1(a5)
	move.w #$83C0,DMACON(a5)	;DMAEN=1, COPEN=1, BPLEN=1, COPEN=1, BLTEN=1



;---------- Création d'une police 16x16 à partir d'une police 8x8 ----------

;Préparer les données de la police (1er octet = suite des bits 7 des 8 lignes / octets du caractère, 2ème octet = suite des bits 6 des 8 lignes / octets du caractère, etc. : rotation de -90°). Noter qu'au Blitter il faudra donc tracer les colonnes de la dernière à la première ligne du fait de l'orientation du motif (il faudrait lui appliquer une symétrie d'axe Y avant pour tracer de la première à la dernière ligne)
	lea 	font8,a0
	move.l 	Font16_PTR,a1
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

	







	

;---------- Boucle principale ----------

	;A1=PTR sur le .w de la colonne du car 16x16
	;A5=$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	
	clr.w	D7		
	move.l	#Texte_Char,a4
	
	
_loop:
	IFNE CTR
	move.l	BltCTR,BltWait
	move.l	#0,BltCtr
	ENDC
	;Attendre que le faisceau d'électrons a terminé de tracer l'écran

	;D0 = ctr de boucle
_waitVBL:
	move.l VPOSR(a5),d0
	lsr.l #8,d0
	and.w #$01FF,d0
	cmp.w #DISPLAY_Y+DISPLAY_DY,d0
	blt _waitVBL
	
	;Registres à ne pas modifier
	;A1,A4,A5,D7
	
	IFNE DEBUGDISPLAYTIME
	move.w #$0F00,COLOR00(a5)
	ENDC

	;----- PERMUTER LES BITPLANE ----------
	;Permuter circulairement les bitplanes
	;Registres à ne pas modifier
	;A1,A4,A5,D7
	move.l bitplaneA,d0
	move.l bitplaneB,d1
	move.l bitplaneC,d2
	move.l d1,bitplaneA	;Bitplane Affiché
	move.l d2,bitplaneB	;Bitplane en construction
	move.l d0,bitplaneC ;Bitplane en effacement

	;D0,D1,D2 libérés
	;A1,A4,A5,D7 gardés
	
	;----- ADRESSE DES BITPLANE DANS COPPERLIST ----------
	;ecriture des adresses bitplane dans la copperlist
	movea.l	Copperlist_BitPlanes_PTR,a0
	
	;BitplaneA0
	move.w 	d1,2(a0)
	swap 	d1
	move.w 	d1,6(a0)
	swap 	d1
	add.l	#TAILLE_BITPLANE,d1
	;BitplaneA1
	move.w d1,10(a0)
	swap 	d1
	move.w d1,14(a0)
	swap 	d1
	add.l	#TAILLE_BITPLANE,d1
	;BitplaneA2
	move.w d1,18(a0)
	swap 	d1
	move.w d1,22(a0)

	
	;A1,A4,A5,D7 gardés
	
	; ;Afficher le sine scroll (d0 doit être l'offset du sinus de l'angle courant)
	; WAITBLIT
	; move.w #4*(LINE_DY-LINE_DX),BLTAMOD(a5)
	; move.w #4*LINE_DY,BLTBMOD(a5)
	; move.w #DISPLAY_DX>>3,BLTCMOD(a5)
	; move.w #DISPLAY_DX>>3,BLTDMOD(a5)
	; move.w #(4*LINE_DY)-(2*LINE_DX),BLTAPTL(a5)
	; move.w #$FFFF,BLTAFWM(a5)
	; move.w #$FFFF,BLTALWM(a5)
	; move.w #$8000,BLTADAT(a5)
	; move.w #(LINE_OCTANT<<2)!$F041,BLTCON1(a5)		;BSH3-0=15, SIGN=1, OVF=0, SUD/SUL/AUL=octant, SING=0, LINE=1


	;ecriture d'un texte 8x8
	;A1,A4,A5,D7 ne pas modifier
	;A0,A2,A3,D0 utilisés


*** AFFICHER UN TEXTE ********************************
*	
*	
	IFNE AffTexteFixe
	
	IFNE DEBUGDISPLAYTIME
	move.l 	bitplaneB,a2
	add.l	#TAILLE_BITPLANE,a2
	lea	TexteAngle,a3
	add.l	#0*8*5+35,A2	;posx en octet (pas de 8 pix)
	Jsr	_bclAffTexte
	ENDC
	
	
	move.l 	bitplaneB,a2
	add.l	#TAILLE_BITPLANE,a2
	lea	TexteAAfficher,a3
	add.l	#40*8*5+0,A2	;posx en octet (pas de 8 pix)
	Jsr	_bclAffTexte
	
	

	bra	_FinAFFTexte	

	
_bclAffTexte:
	moveq.l	#0,d0
	move.b	(a3)+,d0	;on lit le caratère
	beq	_finTexte	;si 0 on est  la fin du texte
	
	sub.b	#$20,d0	;la table commence au caractère " "
	lsl.w	#3,d0	;8 octets / caractère
	;lea		Police8x8,a0
	lea	font8,a0
	add.l	d0,a0
	move.w	#8-1,d0
.aff8x8:
	move.b	(A0)+,(A2)
	add.l	#40,a2	;ligne suivante
	dbf	d0,.aff8x8
	;fin de cara
	sub.l	#40*8-1,a2	;position car suivant
	bra	_bclAffTexte
_FinTexte:
	rts

	

TexteAAfficher:
	dc.b	"Rotation Rubiks 3D - Arnaud 2020-11",0
	even
TexteAngle:
	dc.b	"Angle",0
	even

_FinAFFTexte:
	ENDC
*
*	
*** FIN AFFICHER UN TEXTE ********************************




*** SCROLL TEXT ********************************
*
*	
	
	IFNE AffScroll
	
	;SCROLLING HORIZONTAL
	;A5=#$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	;A1,A4,A5,D7 ne pas modifier
	
	;*** Copier la zone TEXTE de BitplaneA vers BitplaneB 
	;avec décalage de n pixel de scroll
	IFNE BLITTER
	;Blitter
	
	;http://amiga-dev.wikidot.com/hardware:bltcon0
	;http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node001A.html
	
	move.l 	bitplaneA,a2
	add.l	#TAILLE_BITPLANE,a2	;bitplaneA1
	
	add.l	#SCROLL_POS_Y*40,a2	;1 ligne = 40 octets
	move.l 	bitplaneB,a3
	add.l	#TAILLE_BITPLANE,a3	;bitplaneA1
	add.l	#SCROLL_POS_Y*40-2,a3

	WAITBLIT
	move.l #$F9F00000,BLTCON0(a5)	; ascending mode
									; set usage of sources and minterm
                                    ; $9 = use sources A and D = %1001
                                    ; $f0 = minterm = A
	move.l #$7fffffff,BLTAFWM(a5)	;masking of first/last word
	move.w #0,BLTAMOD(a5)		;A modulo=bytes to skip between lines
	move.w #0,BLTDMOD(a5)	;D modulo en octet mais pair
	move.l a2,BLTAPTH(a5)	;source graphic top left corner
	move.l a3,BLTDPTH(a5)	;destination top left corner
	move.w #16<<6+(DISPLAY_DX/16),BLTSIZE(a5)	;16 lignes * 20 mots de large, starts blit
	WAITBLIT
	;BLTSIZE
	;Bit    15 	14 	13 	12 	11 	10 	09 	08 	07 	06 	05 	04 	03 	02 	01 	00
	;       H9 	H8 	H7 	H6 	H5 	H4 	H3 	H2 	H1 	H0 	W5 	W4 	W3 	W2 	W1 	W0
	;H = Height = Vertical lines (10 bits = 1024 lines max)
	;W = Width = Horiz pixels (6 bits = 64 words = 1024 pixels max)
	
	
	ELSE
	;CPU
	;D0=ctr boucle
	;D1=Data source de gauche
	;D2=data source de droite
	;A2=Bitplane Source
	;A3=Bitplane Dest
	;A1,A4,A5,D7 ne pas modifier
	
	move.l 	bitplaneA,a2
	add.l	#TAILLE_BITPLANE,a2	;on change de bitplane
	add.l	#SCROLL_POS_Y*40,a2	;1 ligne = 40 octets
	move.l 	bitplaneB,a3
	add.l	#TAILLE_BITPLANE,a3	;on change de bitplane
	add.l	#SCROLL_POS_Y*40,a3
	move.w	#10*16-1,d0
_Bcl_Move_CPU:
	move.l	(a2)+,d1		;data source de gauche
	lsl.l	#SCROLL_SPEED,d1	;on decalde n pixels vers la gauche
	move.b	(A2),d2			;on prend le car de droite à déplacer
	lsr.b	#8-SCROLL_SPEED,d2
	or.b	d2,d1
	move.l	d1,(a3)+
	dbf	d0,_Bcl_Move_CPU
	ENDC
	
	
	;*** ajouter au BitPlaneB les colonnes de caractère correspondant au trou réalisé par le décalage
	;A1=PTR sur le .w de la colonne du car 16x16
	;A5=$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	
	;D1=ligne de caractères à injecter
	;D0=ctr de 15 pix
	;D2=car à modifier
	;A3=bitplane Dest
	
	move.w	(a1),d1	
	;move.w	#%1011111110101001,d1	;pour le moment compteur
		
	move.l 	bitplaneB,a3
	add.l	#TAILLE_BITPLANE,a3	;bitplaneA1
	
	add.l	#(SCROLL_POS_Y+15)*40+40-1,a3 ;on se place sur le dernier octet de la premiere ligne
	move.w	#16-1,D0
_Bcl_Creer_Col_Car:
	move.b	(A3),d2
	btst	d0,d1
	beq	_pixEmpty
	;pix=1
	bset	#0,d2
	bra	_PixEnd
_pixEmpty:
	bclr	#0,D2
_pixEnd:
	move.b	d2,(a3)
	sub.l	#40,a3	;ligne suivante +40 octets
	dbf	d0,_Bcl_Creer_Col_Car
	
	
	
	;A1,A4,A5,D7 ne pas modifier
	
	;*** incrémenter de n pixels et d'un car si on change de 15 pix
	;A1=PTR sur le .w de la colonne du car 16x16
	;A5=$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	
	add.w	#1,d7
	btst	#4,d7
	beq		_PasResetColAff	;beq si bit a 0
	clr.w	d7
	clr.w	d2
	move.b	(a4)+,D2
	bne		_pasFinTexte
	move.l	#Texte_Char,a4
	move.b	(a4),D2
_pasFinTexte:
	sub.b	#$20,d2
_PasResetColAff:





	;*** determine lignedata à afficher
	;A1=PTR sur le .w de la colonne du car 16x16
	;A5=$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	
	clr.l	d2
	move.l	Font16_PTR,a1
	move.b	(a4),D2
	sub.b	#$20,d2
	lsl.w	#5,d2	;on multiplie par 32 octets car 1 car 16x16pix =32 octets
	add.l	d2,a1
	add.l	d7,a1	;on ajoute la position colonne de 15pix donc 2 octets
	add.l	d7,a1

	
	
	;Registres Globaux
	;A1=PTR sur le .w de la colonne du car 16x16
	;A5=$DFF000
	;A4=adresse du caractère du texte à afficher
	;D7=position de la colonne à afficher 0..15
	;A1,A4,A5,D7 ne pas modifier
	
	ENDC
	;utilisés: d0,d1,d2,d3,d4,d5,d6,A0
*
*
*** FIN SCROLL TEXT ***************************



	


*** CALCUL 3D ********************************
*
*	
	IFNE Calculer3D
	
Calcul3D:
    
	movem.l d0-d7/a0-a6,-(sp)

	;------- Calcul des angles ---------
	
    ;Angles de visualisation
	;move.l	#0,a4
	;move.l	#0,a5
	;move.l	#0,a6
	
	;TODO OPTIMISER
	;Table SIN et COS sur 1 tour = 256
	;à 256 le registre passe à 00 sur 8 bits
	;ainsi pas de comparaison ni de Blo
	;Gain = 1 VBL
	
    ;Increment angle aX
	move.w	AngleAx,a4
	add.w  	#PasAngleAX,a4  ;increment
	cmp.w	#360,a4
	blo     PasModuloIncrementAx
    sub.w   #360,a4	
PasModuloIncrementAx:
	move.w	a4,AngleAx

    ;Increment angle aY
	move.w	AngleAY,a5
	add.w  	#PasAngleAY,a5  ;+increment
	cmp.w	#360,a5
	blo     PasModuloIncrementAy
    sub.w   #360,a5
PasModuloIncrementAy:
	move.w	a5,AngleAy
	
    ;Increment angle aZ
	move.w	AngleAz,a6
	add.w  	#PasAngleAZ,a6 	;increment
	cmp.w	#360,a6
	blo     PasModuloIncrementAz
    sub.w   #360,a6
PasModuloIncrementAz:
	move.w	a6,AngleAz
   
	;calage table en mots donc angle*2
	add.w	a6,a6
	add.w	a5,a5
  	add.w	a4,a4
   
   
	lea CosinusTbl,A2
   	lea SinusTbl,A3
    
	;------- Calcul des normales ---------
	;par rotation du vecteur normale
	;autre solution : par calcul du vecteur normale mais nécessite d'avoir calculé les 3 points en 3D
	;autre solution : calculer la normale de la pièce centrale
	;normale = (yuzv-zuyv,-xuzv+zuxv,xuyv-yuxv)
	;     si on prend que la composante Y cela revient à calculer Ny=-Xu*Zv+ZuXv
	
	lea	Poly,a0
	lea	polygoneCalcules,a1

	move.l	#NBPOLY-1,d7	;nb de polygones
BclCalculerNormales:
		;TODO OPTIMISER
		;Mettre les données calculees à la suite des données de base, on utilise un seul registre A0
		;mais risque d'impacter le calcul des points plus loin
		
		move.w	(A0)+,d0	;nx
		move.w	(A0)+,d1	;ny
		move.w	(A0)+,d2	;nz
		bsr     CalculerXYZ
		move.w  d4,(A1)+    ;x
		move.w  d0,(A1)+    ;y
		move.w  d1,(A1)+    ;z
		add.l	#32-6,a0
		add.l	#32-6,a1
	dbf	d7,BclCalculerNormales
	
	;------- Calcul des points dont les normales sont orientées vers observateur ---------
	;y représente la profondeur, si y> alors face visibel
	;POLY:    dc.w    -50,0,0, 2, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
	
	lea	Poly,a0
	lea	polygoneCalcules,a1
	add.l	#1*2,a0
	add.l	#1*2,a1
	
	move.l	#NBPOLY-1,d7	;nb de polygones
BclCalculerPoints:
		move.w	(a1),d0	;normale Y
		bpl		NormaleVersFond	;saute si d0>=0 cad normale vers le fond

		add.l	#2*2,a0	;on se cale sur la couleur
		add.l	#2*2,a1
		move.w	(A0)+,(a1)+	;copie de la couleur
		
		;TODO OPTIMISER
		;calculer le 4 eme point D à l'aide des 3 autres A,B,C
		;vecteur(AB)=vecteur(CD)
		
		; REPT 4
		; move.w	(A0)+,d0	;x
		; move.w	(A0)+,d1	;y
		; move.w	(A0)+,d2	;z
		; bsr     CalculerXYZ
		; add.w	#offsetX,d4		;emplacement ecran
		; add.w	#offsetZ,d1
		; move.w  d4,(A1)+    ;x
		; move.w  d0,(A1)+    ;y
		; move.w  d1,(A1)+    ;z
		; ENDR
		;add.l	#1*2,a0
		;add.l	#1*2,a1

		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		bsr     CalculerXYZ
		add.w	#offsetX,d4		;emplacement ecran
		add.w	#offsetZ,d1
		move.w  d4,0(A1)    ;x
		move.w  d0,2(A1)    ;y
		move.w  d1,4(A1)    ;z
		
		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		bsr     CalculerXYZ
		add.w	#offsetX,d4		;emplacement ecran
		add.w	#offsetZ,d1
		move.w  d4,6(A1)    ;x
		move.w  d0,8(A1)    ;y
		move.w  d1,10(A1)    ;z

		move.w	(A0)+,d0	;x
		move.w	(A0)+,d1	;y
		move.w	(A0)+,d2	;z
		bsr     CalculerXYZ
		add.w	#offsetX,d4		;emplacement ecran
		add.w	#offsetZ,d1
		
		move.w  d4,12(A1)    ;xC
		move.w  d0,14(A1)    ;y
		move.w  d1,16(A1)    ;z


		;---Calcul du 4eme point par Vecteur AB=CD
		;Gagne 50 VBL
		;---x4
		add.w	0(a1),d4	;X3+X1
		sub.w	6(a1),d4	;X3+X1-X2
		move.w  d4,18(A1)   ;x4
		;---y4
		add.w	2(a1),d0
		sub.w	8(a1),d0
		move.w  d0,20(A1)
		;---z4
		add.w	4(a1),d1
		sub.w	10(a1),d1
		move.w  d1,22(A1)
		
		
		add.l	#3*2+1*2,a0
		add.l	#12*2+1*2,a1
		
	dbf		d7,BclCalculerPoints
	bra		FinBclCalculerPoints
	
NormaleVersFond:
		;on calcule pas
		add.l	#32,a0
		add.l	#32,a1
	dbf	d7,BclCalculerPoints
	
 FinBclCalculerPoints:
   
   
   
   
   ; ;on calcule les points de la table
; CalculerEnsemblePointsXYZ:
    ; lea Points,a0
    ; lea PointsCalcules,a1
    ; lea CosinusTbl,A2
    ; lea SinusTbl,A3
    
    ; move.w  #(FinPoints-Points)/6-1,d7
    
; BoucleCalculerEnsemblePointsXYZ:
    ; clr.l   D0
    ; clr.l   d1
    ; clr.l   d2
    ; clr.l   d5
    ; clr.l   d6
    
    ; move.w  (A0)+,d0    ;x
    ; move.w  (A0)+,d1    ;z
    ; move.w  (A0)+,d2    ;z
	
	; bsr     CalculerXYZ
    
	; add.w	#offsetX,d4		;emplacement ecran
	; add.w	#offsetZ,d1
	
	; move.w  d4,(A1)+    ;x
    ; move.w  d0,(A1)+    ;y
    ; move.w  d1,(A1)+    ;z
    ; dbf     d7,BoucleCalculerEnsemblePointsXYZ
; FinCalculerEnsemblePointsXYZ:    
    
	bra 	FinCalcul3D


CalculerXYZ:
    ;Entree :   D0=x , D1=y, D2=Z
    ;           D3=aX, D4=aY
    ;           A2=ptrTableCOS, A3=ptrTableSIN
    ;Sortie :   D0=x, D1=z, D2=y
    ;Interne: 

	;************************
	;coordonnées cartesiennes
  
	;utilisé : d0=X, d1=Y, d2=Z, a2=cos, a3=sin, A4=aX, A5=aY, a6=aZ
    
	;************************
    ;rotation axe Z (plan XY)   
    ;x1=x*cos(aZ)-y*sin(aZ) 	;    
    ;y2=x*sin(aZ)+y*cos(aZ)    
    
	move.w  (a2,A6),d4  ;d4=cos(aZ) 
    move.w  (a3,A6),d3  ;d3=sin(aZ)
    
    move.w  d4,d5	;cos
    move.w  d3,d6	;sin
    
    muls    d0,d5	;x*cos
    muls    d1,d6	;y*sin
    sub.l   d6,d5   ;d5=x1  
    lsr.l   #7,d5
    lsr.l   #7,d5
    
    muls    d0,d3	;x*sin
    muls    d4,d1	;y*cos
    add.l   d3,d1  	;d1=y1
    lsr.l   #7,d1	;22 cylcles
    lsr.l   #7,d1  	;+22d0=
    
   
	;d5=x1, d1=y1
  
    ;************************
    ;utilisé : d1=y1, d2=Z, d5=x1, a2=cos, a3=sin, A4=aX, A5=aY
    ;************************
    ;rotation axe X (plan YZ)   ;D4=cos(A4), d3=sin(A4)
    ;y2=y1*cos(aX)-z*sin(ax)    ;d0=D4, d0=d1*d0, d6=d3, d6=d2*d6, d0=d0-d6 
    ;z1=y1*sin(aX)+z*cos(aX)    ;d3=d1*d3, d4=d2*d4, d3=d3+d4
    
	move.w  (a2,A4),d4  ;a4=cos(aX)
    move.w  (a3,A4),d3  ;d3=sin(ax)
    
    move.w  d4,d0	;c
    move.w  d3,d6	;s
    
    muls    d1,d0	;y1*cos
    muls    d2,d6	;z*sin
    sub.l   d6,d0   ;y2=y1*cos-z*sin  
    lsr.l   #7,d0
    lsr.l   #7,d0
    
    muls    d1,d3	;y*sin
    muls    d2,d4	;z*cos
    add.l   d4,d3   ;z1=y*sin+z*cos
    lsr.l   #7,d3
    lsr.l   #7,d3
    
    ;************************
    ;utilisé : d0=y2, d3=z1, d5=x1, a2=cos, a3=sin, A5=aY
    ;************************
    ;rotation axe Y (plan ZX)   ;d6=cos(A5), d4=sin(A5)
    ;z2=z1*cos(aY)-x1*sin(aY)   ,d1=d6, d1=d3*d1, d2=d4, d2=d5*d2, d1=d1-d2 
    ;x2=z1*sin(aY)+x1*cos(aY)   ;d6=d5*d6, d4=d3*d4, d4=d6+d4
    
	;TODO OPTIISATION
	;Faire une rotation sur 2 axes, donc blanquer le 3eme axe
	;Gagne 35 VBL
	;move.W	d5,d4
	;move.w	d3,d1
	;rts
	
    
    move.w  (a2,A5),d6  ;cos(aY)
    move.w  (a3,A5),d4  ;sin(aY)
    
    move.w  d6,d1
    move.w  d4,d2
    
    muls    d3,d1	;z1*cos
    muls    d5,d2	;x1*sin
    sub.l   d2,d1   ;z2=z1*cos-x1*sin
    lsr.l   #7,d1
    lsr.l   #7,d1
    
    muls    d3,d4	;z1*sin
    muls    d5,d6	;x1*cos
    add.l   d6,d4   ;x2=x1*cos+z1*sin
    lsr.l   #7,d4
    lsr.l   #7,d4
    
    ;************************
    ;utilisé : d0=y2, d1=z2, d4=x2

    rts

FinCalcul3D:
	movem.l (sp)+,d0-d7/a0-a6
	  
	ENDC
*
*
*** FIN CALCUL 3D ***************************
	
	
	
	
	
	
*** TRACER AU BLITTER ********************************
*
*
	IFNE AffLigneBlitter
	movem.l d0-d7/a0-a6,-(sp)
	;clr.l	d7
	clr.l	d0
	
	WAITBLIT
	move.w	#40,BLTCMOD(A5)	;=largeur du plan de pixel en octets
	move.w	#40,BLTDMOD(A5)	;=largeur du plan de pixel en octets
	move.w	#$8000,BLTADAT(A5)
	move.w	#$FFFF,BLTBDAT(A5) 	:texture de la droite, $FFFF = pleine
	move.w	#$FFFF,BLTAFWM(A5)	;=$FFFF
	move.w	#$FFFF,BLTALWM(A5)	;=$FFFF
	lea	TableOctant(pc),a0

	move.l	bitplaneB,A1	;A1 et A2 utilisés comme copie dans la boucle

	
	
	;----- TRACE DU RUBIKS ---------

	lea	polygoneCalcules,a3
	add.l	#1*2,a3	;on se cale sur normaleY
	
	move.l	#NBPOLY-1,d7	;nb de polygones
BoucleTracerRubiks;
	;dc.w    -50,0,0, 2, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
	;dc.w    nx,ny,nz, coul, x1,y1,z1, , x2,y2,z2, x3,y3,z3, x4,y4,z4
	moveq.l	#0,d0
	
	move.w	(A3),d0
	bpl		PasDeTracerRubiks	;saute si d0>=0
	;on trace
	moveq.l	#0,d1
	moveq.l	#0,d2
	moveq.l	#0,d3
	
	add.l	#3*2,A3	
	
	move.w	0(a3),d0	;x1
	move.w	4(a3),d1	;z1
	move.w	6(a3),d2	;x2
	move.w	10(a3),d3	;z2
	bsr		_TracerLigne
	
	moveq.l	#0,d0
	moveq.l	#0,d1
	moveq.l	#0,d2
	moveq.l	#0,d3
	move.w	6(a3),d0	;x1
	move.w	10(a3),d1	;z1
	move.w	12(a3),d2	;x2
	move.w	16(a3),d3	;z2
	bsr		_TracerLigne
	
	moveq.l	#0,d0
	moveq.l	#0,d1
	moveq.l	#0,d2
	moveq.l	#0,d3
	move.w	12(a3),d0	;x1
	move.w	16(a3),d1	;z1
	move.w	18(a3),d2	;x2
	move.w	22(a3),d3	;z2
	bsr		_TracerLigne
	
	moveq.l	#0,d0
	moveq.l	#0,d1
	moveq.l	#0,d2
	moveq.l	#0,d3
	move.w	18(a3),d0	;x1
	move.w	22(a3),d1	;z1
	move.w	0(a3),d2	;x2
	move.w	4(a3),d3	;z2
	bsr		_TracerLigne
	
	
	add.l	#6*2,A3	
	add.l	#7*2,A3	
	
	dbf		d7,BoucleTracerRubiks
	bra		FinDeTracerRubiks
	
PasDeTracerRubiks:
	;on trace pas, on passe au polygonne suivant
	add.l	#32,a3
	
	dbf	d7,BoucleTracerRubiks
	
FinDeTracerRubiks:	
	
	
	
	
; ;tracé de l'objet 3D
	 IFNE AffObjet3D ************************** TRACER OBJET 3D
	; lea		PointsCalcules,a3 ******* DEBUG
	; lea		Lignes,a4

	; move.w  #((FinLignes-Lignes)/4)-1,d7
; BoucleTracer3D:
	; moveq.l	#0,d0
	; moveq.l	#0,d1
	; moveq.l	#0,d2
	; moveq.l	#0,d3
	
	; move.w	(a4)+,d3	;offset 1er point
	; move.w	(a3,d3),d0	;x1
	; move.w	4(a3,d3),d1	;y1 (z)
	
	; move.w	(a4)+,d3	;offset 2eme point
	; move.w	(a3,d3),d2	;x2
	; move.w	4(a3,d3),d3	;y2 (z)
	
	; bsr		_TracerLigne
	
	; dbf	d7,BoucleTracer3D


	;tracé des axes de rotation
	IFNE DEBUGDISPLAYTIME ************************** DEBUG
	
	lea	CosinusTbl,a3
	lea	SinusTbl,A4

	lea		AngleAx,a6
	
	moveq.l	#3-1,d7
BoucleAffAngles:
	move.l	#290,d0	;x1
	move.l	#30,d1	;y1
	move.l	#20,d4	;rayon

	;ajout du pas y
	moveq.l	#0,d5
	move.w	d7,d5
	muls	#40,d5
	add.w	d5,d1
	
	moveq.l	#0,d5
	move.w	(a6)+,d5	;angle AX, AY, AZ
	add.w	d5,d5		;angle table 

	move.w	(a3,d5),d2	;attention adressage pair
	muls	d4,d2
	lsr.l	#7,d2
	lsr.l	#7,d2 ;x2
	add.l	d0,d2

	move.w	(a4,d5),d3	;attention adressage pair
	muls	d4,d3
	lsr.l	#7,d3
	lsr.l	#7,d3	;y2
	add.l	d1,d3
	
	bsr	_TracerLigne

	dbf	d7,BoucleAffAngles
	
	ENDC ************************** FIN DEBUG
	
	
	movem.l (sp)+,d0-d7/a0-a6
	
	bra	_FinTracerBlitter

	; a:	dc.l	0
	; x1:	dc.l	0
	; y1:	dc.l	0
	; x2:	dc.l	0
	; y2:	dc.l	0
	
	ENDC ************************** FIN TRACE OBJET 3D
	
	
	
_TracerLigne:
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
	;Arguments (d0=x1,d1=y1,d2=x2,d3=y2)
	;utilisés : d4,a0,a1
	;d0..d4,A0

	moveq.l	#0,d4	;4 cycles
	sub.w	d1,d3	;d3=dy=y2-y1
	bpl.b	y2_sup_y1
	bset	#2,d4	;8 cycles
	neg.w	d3		;d3=abs(dy)
y2_sup_y1:
	sub.w	d0,d2	;d2=dx=x2-x1
	bpl.b	x2_sup_x1
	bset	#1,d4	
	neg.w	d2		;d2=abs(dx)
x2_sup_x1:
	cmp.w	d3,d2	;D3=dy vs D2=dx	
	bpl.b	dX_sup_dY
	bset	#0,d4
	exg		d2,d3
dX_sup_dY:

	move.b	(a0,d4),d5	;octant dans D5

	;d3=dy=petit delta
	;d2=dx=GRAND DELTA
	
	;---- Adresse de départ ----
	;D0=x1, D1=y1
	;d2=dx,	d3=dY
	
	move.l	a1,a2	;BitplaneB ;4 cycles

	ror.l   #4,d0   ;move upper four bits into hi word
    add.w	d0,d0	;d0=d0*2
	add.l	d0,a2	;bitplaneB+x1/8
					;l'adressage étant sur 24 bits les 4 bits HI n'influent pas
	
	;d1=y1
	;36 cycles
	lsl.w	#3,d1	;d1=y1*8
	add.w	d1,a2	;A2=bitplaneB+(x1/8)+y1*8
	add.w	d1,d1	;d1=y1*16
	add.w	d1,d1	;d1=y1*32
	add.l	d1,a2	;a2=bitplaneB+(x1/8)+y1*40 = adresse de départ	

	moveq.l	#0,d6	;clr.l	d6	;,d1
	
	;d3=dY 
	add.w   d3,d3	;d3=dy*2
    add.w   d3,d3	;d3=dy*4	;;lsl.w	#2,d3		;10 cycles
	move.w	D3,D4	;D4=4*dy 
	move.w	d2,d1	;d1=d2=dX 
	add.w	d1,d1	;lsl.w	#1,d1	;D1=2*dx
	
	WAITBLIT
	move.w	d3,BLTBMOD(A5)	;=4*dy
	sub.w	d1,D3	;d3=4*dy - 2*dx
	roxl.w	#7,D6	;si D3<0, placer le bit SIGN à 1 dans BLTCON1 
	
	move.l	d3,BLTAPTH(A5)	;=4*dY-2*dX, 

	add.w	d1,d1	;lsl.w	#1,d1	;D1=2*2*dx
	sub.w	D1,D4	;d4=4*dy-4*dx
	move.w	d4,BLTAMOD(A5)	;=4*dy-4*dx
	
	swap	d0
	or.w	d6,D0
	or.w	#$0BCA,D0
	
	move.w	d0,BLTCON0(A5)	;bits 15,14,13,12  = point de départ de la droite
				;bit 11,10,9,8 = %1011
				;bit 7..0 = $CA
	or.w	D6,D5	;%xxxx000000xxxx01
	
	;bset	#1,D5	;pour tracer un seul pt par ligne 
	;l'inscrire directement dans Tableoctant pour éviter une instruction
	
	move.l	a2,BLTCPTH(A5)	;adresse du point de départ de la droite
	move.l	a2,BLTDPTH(A5)	;idem
	move.w	d5,BLTCON1(A5)	;bits 15,14,13, 12  = point de départ de la droite
				;bits 11..7 = %00000
				;bit 6 = 1 si 4*dY-2*dX<0
				;bit 5 = 0
				;bits 4,3,2 = code Octant
				;bit 1 = 1, 1 point par ligne
				;bit 0 = 1 mode tracé de droite
	
	add.w	#$01,d2	;dx+1
	lsl.w	#6,d2	;(dx+1)*64 ; 20 cycles
	add.w	#$02,d2	;(dx+1)*64+2
	move.w	d2,BLTSIZE(A5)	;c'est parti = (dX+1)*64+2
	
	rts
	
TableOctant:	;3 premiers bits=octant, bit1 = 1 si 1 pt /ligne, bit 0=1 mode tracé de ligne
	dc.b	%10001
	dc.b	%00001
	dc.b	%10101
	dc.b	%01001
	dc.b	%11001
	dc.b	%00101
	dc.b	%11101
	dc.b	%01101
	even


	ENDC
	**
	**
	**** FIN TRACE AU BLITTER *******************

	IFNE CTR
BltWait:	dc.l	0
BltCtr:		dc.l	0
	ENDC	
	
_FinTracerBlitter:
	
	

	*** Effacer le bitplane caché ************************
	IFNE EffacerBitPlaneCache
	WAITBLIT
	move.w	#0,BLTDMOD(a5)
	move.w	#$0000,BLTCON1(a5)
	move.w	#%0000000100000000,BLTCON0(a5)
	move.l	bitplaneC,BLTDPTH(a5)
	move.w	#(DISPLAY_DX>>4)!(DISPLAY_DY<<6),BLTSIZE(a5)
	ENDC
	
	IFNE DEBUGDISPLAYTIME
	move.w	#$00F0,COLOR00(a5)
	ENDC
	
	
;********** DEBUGDISPLAYTIME (start) **********
;affiche en décimal le nombre de lignes écoulées depuis la fin de l'écran (depuis la ligne DISPLAY_Y+DISPLAY_DY incluse)
	;la trame se termine en DISPLAY_Y+DISPLAY_DY-1
	;le temps est donc compté en nombre de ligne à partir de DISPLAY_Y+DISPLAY_DY incluse
	IFNE DEBUGDISPLAYTIME
	movem.l	d0-d2/a0-a3,-(sp)
	clr.w	d0
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
;=>d0.w = # de lignes prises par les calculs à afficher
	and.l	#$0000FFFF,d0
	moveq	#0,d1
	moveq	#3-1,d2
_timeLoopNumber:
	divu	#10,d0		;=> d0=reste:quotient de la division de d0 sur 32 bits
	swap	d0
	add.b	#$30-$20,d0	;code ASCII de "0" moins l'offset de début dans font8 ($20)
	move.b	d0,d1
	lsl.l	#8,d1
	clr.w	d0
	swap	d0
	dbf 	d2,_timeLoopNumber
	divu 	#10,d0		;=> d0=reste:quotient de la division de d0 sur 32 bits
	swap 	d0
	add.b	#$30-$20,d0	;code ASCII de "0" moins l'offset de début dans font8 ($20)
	move.b	d0,d1
	;=> d1 : suite des 4 offset ASCII dans la police des 4 chiffres à afficher, mais en sens inverse (ex: 123 => "3210")
	lea 	font8,a0
	movea.l	bitplaneB,a1
	moveq 	#4-1,d0
_timeLoopDisplay:
	clr.w 	d2
	move.b 	d1,d2
	lsl.w 	#3,d2
	lea 	(a0,d2.w),a2
	move.l 	a1,a3
	moveq	#8-1,d2
_timeLoopDisplayChar:
	move.b	(a2)+,(a3)
	lea 	DISPLAY_DX>>3(a3),a3
	dbf 	d2,_timeLoopDisplayChar
	lea 	1(a1),a1
	lsr.l	#8,d1
	dbf		d0,_timeLoopDisplay
	movem.l	(sp)+,d0-d2/a0-a3
	ENDC
	
	;********** DISPLAYTIME (end) **********

	;Tester la pression du bouton gauche de la souris

	btst	#6,$bfe001
	bne		_loop
	
	
	
_loopEnd:
	WAITBLIT

;---------- Finalisations ----------


exit:

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

	lea graphicslibrary,a1
	movea.l $4,a6
	jsr -408(a6)
	move.l d0,a1
	move.l 38(a1),COP1LCH(a5)
	clr.w COPJMP1(a5)
	jsr -414(a6)

;Rétablir le système

	movea.l $4,a6
	jsr -138(a6)

;Libérer la mémoire

	movea.l Font16_PTR,a1
	move.l #256<<5,d0
	movea.l $4,a6
	jsr -210(a6)
	movea.l bitplaneA,a1
	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	movea.l $4,a6
	jsr -210(a6)
	movea.l bitplaneB,a1
	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	movea.l $4,a6
	jsr -210(a6)
	movea.l bitplaneC,a1
	move.l #DISPLAY_DEPTH*TAILLE_BITPLANE,d0
	movea.l $4,a6
	jsr -210(a6)
	movea.l copperlist_PTR,a1
	move.l #COPSIZE,d0
	movea.l $4,a6
	jsr -210(a6)

;Dépiler les registres

	movem.l (sp)+,d0-d7/a0-a6
	rts

;---------- Données ----------

graphicslibrary:
	DC.B "graphics.library",0
	EVEN
font8:	INCBIN "sources:sinescroll/font8.fnt"	;32 à 127
	EVEN
		
Texte_Char:		;blk.b	24," "
		DC.B 	"Quelle satisfaction de refaire de l'assembleur 68000 ! ... ",0
		dc.b	"Bug si affiche",0
		EVEN
			
TEXT_POS:			dc.l	0
dmacon_PTR:			DC.w	0
intena_PTR:			DC.w	0
intreq_PTR:			DC.w	0
scrollColumn:			DC.W	0
scrollChar:			DC.W	0
angle:				DC.W	0
copperlist_PTR:			DC.L 	0
Copperlist_BitPlanes_PTR:	dc.l	0
Font16_PTR:			DC.L 	0
bitplaneA:			DC.L 	0
bitplaneB:			DC.L 	0
bitplaneC:			DC.L 	0



********************* COPPER LIST *********************

CopListDataStart:
	;Configuration de l'écran
	dc.w DIWSTRT,(DISPLAY_Y<<8)!DISPLAY_X	; & = AND, ! = OR , ~ = EOR
	dc.w DIWSTOP,((DISPLAY_Y+DISPLAY_DY-256)<<8)!(DISPLAY_X+DISPLAY_DX-256)
	dc.w BPLCON0,(DISPLAY_DEPTH<<12)!$0200
	dc.w BPLCON1,SHADOW_DX<<4	;PF2H=Playfield 2 horizontal scroll code
	dc.w BPLCON2,0
	dc.w DDFSTRT,((DISPLAY_X-17)>>1)&$00FC
	dc.w DDFSTOP,((DISPLAY_X-17+(((DISPLAY_DX>>4)-1)<<4))>>1)&$00FC	;Ce qui revient ((DISPLAY_X-17+DISPLAY_DX-16)>>1)&$00FC si DISPLAY_DX est multiple de 16
	dc.w BPL1MOD,0
	dc.w BPL2MOD,0

;Adresse des bitplanes

CplBitPlanes:
	dc.w BPL1PTL,0
	dc.w BPL1PTH,0
	dc.w BPL2PTL,0
	dc.w BPL2PTH,0
	dc.w BPL3PTL,0
	dc.w BPL3PTH,0

;Couleurs

	IFNE DEBUGDISPLAYTIME
	dc.w $0186,0		;COLOR04 pas utilisée, pour neutraliser de manière quelconque la modification de COLOR00...
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

;Comptabilité ECS avec AGA

	dc.w FMODE,$0000
	
;Ombre et miroir

	dc.w ((DISPLAY_Y+SCROLL_Y+SHADOW_DY-1)<<8)!$0001,$FF00
	dc.w BPL2MOD,-SHADOW_DY*(DISPLAY_DX>>3)

	dc.w ((DISPLAY_Y+SCROLL_Y+SHADOW_DY)<<8)!$0001,$FF00
	dc.w BPL2MOD,0
	dc.w BPLCON1,SHADOW_DX<<4

	dc.w ((DISPLAY_Y+MIRROR_Y-1)<<8)!$0001,$FF00
	dc.w BPL1MOD,-(DISPLAY_DX>>3)
	dc.w BPL2MOD,(SHADOW_DY-1)*(DISPLAY_DX>>3)

	dc.w ((DISPLAY_Y+MIRROR_Y)<<8)!$0001,$FF00
	dc.w BPLCON1,$0000
	dc.w BPL1MOD,-(DISPLAY_DX>>2)
	dc.w BPL2MOD,-(DISPLAY_DX>>2)
	
	IFNE DEBUGDISPLAYTIME
	dc.w $0188,MIRROR_COLOR	;COLOR04 pas utilisée, pour neutraliser de manière quelconque la modification de COLOR00...
	ELSE
	dc.w COLOR00,MIRROR_COLOR
	ENDC

	dc.w COLOR03,MIRROR_SCROLL_COLOR
;Fin
	dc.l 	$FFFFFFFE
	dc.l	$00c0ffEE
CopListDataEnd:

COPSIZE=CopListDataEnd-CopListDataStart


;---- Angles de rotation objet
AngleAx:		dc.w	InitAngleAx
AngleAy:		dc.w	InitAngleAy
AngleAz:		dc.w	InitAngleAz


;----- Tables Trigo -----
SinusTbl:
   dc.w   0,285,571,857,1142,1427,1712,1996,2280,2563   ;Sin(0) ou Cos(-90)
   dc.w   2845,3126,3406,3685,3963,4240,4516,4790,5062,5334   ;Sin(10) ou Cos(-80)
   dc.w   5603,5871,6137,6401,6663,6924,7182,7438,7691,7943   ;Sin(20) ou Cos(-70)
   dc.w   8191,8438,8682,8923,9161,9397,9630,9860,10086,10310   ;Sin(30) ou Cos(-60)
   dc.w   10531,10748,10963,11173,11381,11585,11785,11982,12175,12365   ;Sin(40) ou Cos(-50)
   dc.w   12550,12732,12910,13084,13254,13420,13582,13740,13894,14043   ;Sin(50) ou Cos(-40)
   dc.w   14188,14329,14466,14598,14725,14848,14967,15081,15190,15295   ;Sin(60) ou Cos(-30)
   dc.w   15395,15491,15582,15668,15749,15825,15897,15964,16025,16082   ;Sin(70) ou Cos(-20)
   dc.w   16135,16182,16224,16261,16294,16321,16344,16361,16374,16381   ;Sin(80) ou Cos(-10)
CosinusTbl:
   dc.w   16384,16381,16374,16361,16344,16321,16294,16261,16224,16182   ;Sin(90) ou Cos(0)
   dc.w   16135,16082,16025,15964,15897,15825,15749,15668,15582,15491   ;Sin(100) ou Cos(10)
   dc.w   15395,15295,15190,15081,14967,14848,14725,14598,14466,14329   ;Sin(110) ou Cos(20)
   dc.w   14188,14043,13894,13740,13582,13420,13254,13084,12910,12732   ;Sin(120) ou Cos(30)
   dc.w   12550,12365,12175,11982,11785,11585,11381,11173,10963,10748   ;Sin(130) ou Cos(40)
   dc.w   10531,10310,10086,9860,9630,9397,9161,8923,8682,8438   ;Sin(140) ou Cos(50)
   dc.w   8191,7943,7691,7438,7182,6924,6663,6401,6137,5871   ;Sin(150) ou Cos(60)
   dc.w   5603,5334,5062,4790,4516,4240,3963,3685,3406,3126   ;Sin(160) ou Cos(70)
   dc.w   2845,2563,2280,1996,1712,1427,1142,857,571,285   ;Sin(170) ou Cos(80)
   dc.w   0,-286,-572,-858,-1143,-1428,-1713,-1997,-2281,-2564   ;Sin(180) ou Cos(90)
   dc.w   -2846,-3127,-3407,-3686,-3964,-4241,-4517,-4791,-5063,-5335   ;Sin(190) ou Cos(100)
   dc.w   -5604,-5872,-6138,-6402,-6664,-6925,-7183,-7439,-7692,-7944   ;Sin(200) ou Cos(110)
   dc.w   -8193,-8439,-8683,-8924,-9162,-9398,-9631,-9861,-10087,-10311   ;Sin(210) ou Cos(120)
   dc.w   -10532,-10749,-10964,-11174,-11382,-11586,-11786,-11983,-12176,-12366   ;Sin(220) ou Cos(130)
   dc.w   -12551,-12733,-12911,-13085,-13255,-13421,-13583,-13741,-13895,-14044   ;Sin(230) ou Cos(140)
   dc.w   -14189,-14330,-14467,-14599,-14726,-14849,-14968,-15082,-15191,-15296   ;Sin(240) ou Cos(150)
   dc.w   -15396,-15492,-15583,-15669,-15750,-15826,-15898,-15965,-16026,-16083   ;Sin(250) ou Cos(160)
   dc.w   -16136,-16183,-16225,-16262,-16295,-16322,-16345,-16362,-16375,-16382   ;Sin(260) ou Cos(170)
   dc.w   -16384,-16382,-16375,-16362,-16345,-16322,-16295,-16262,-16225,-16183   ;Sin(270) ou Cos(180)
   dc.w   -16136,-16083,-16026,-15965,-15898,-15826,-15750,-15669,-15583,-15492   ;Sin(280) ou Cos(190)
   dc.w   -15396,-15296,-15191,-15082,-14968,-14849,-14726,-14599,-14467,-14330   ;Sin(290) ou Cos(200)
   dc.w   -14189,-14044,-13895,-13741,-13583,-13421,-13255,-13085,-12911,-12733   ;Sin(300) ou Cos(210)
   dc.w   -12551,-12366,-12176,-11983,-11786,-11586,-11382,-11174,-10964,-10749   ;Sin(310) ou Cos(220)
   dc.w   -10532,-10311,-10087,-9861,-9631,-9398,-9162,-8924,-8683,-8439   ;Sin(320) ou Cos(230)
   dc.w   -8193,-7944,-7692,-7439,-7183,-6925,-6664,-6402,-6138,-5872   ;Sin(330) ou Cos(240)
   dc.w   -5604,-5335,-5063,-4791,-4517,-4241,-3964,-3686,-3407,-3127   ;Sin(340) ou Cos(250)
   dc.w   -2846,-2564,-2281,-1997,-1713,-1428,-1143,-858,-572,-286   ;Sin(350) ou Cos(260)
   dc.w   -1,285,571,857,1142,1427,1712,1996,2280,2563   ;Sin(360) ou Cos(270)
   dc.w   2845,3126,3406,3685,3963,4240,4516,4790,5062,5334   ;Sin(370) ou Cos(280)
   dc.w   5603,5871,6137,6401,6663,6924,7182,7438,7691,7943   ;Sin(380) ou Cos(290)
   dc.w   8191,8438,8682,8923,9161,9397,9630,9860,10086,10310   ;Sin(390) ou Cos(300)
   dc.w   10531,10748,10963,11173,11381,11585,11785,11982,12175,12365   ;Sin(400) ou Cos(310)
   dc.w   12550,12732,12910,13084,13254,13420,13582,13740,13894,14043   ;Sin(410) ou Cos(320)
   dc.w   14188,14329,14466,14598,14725,14848,14967,15081,15190,15295   ;Sin(420) ou Cos(330)
   dc.w   15395,15491,15582,15668,15749,15825,15897,15964,16025,16082   ;Sin(430) ou Cos(340)
   dc.w   16135,16182,16224,16261,16294,16321,16344,16361,16374,16381   ;Sin(440) ou Cos(350)


; -------------------------------------------------------------------------
;
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
; |___|___|___|/|/                        aY2 |
; |   |   |   | /                            aZ2
; |___|___|___|/
;  
;
;

;
;AXES DE ROTATION
;NumAxeRot=n, aX1=1, aY1=2, aZ1=3, aX2=4, aY2=5, aZ2=6
;
aX1=1
aY1=2
aZ1=3
aX2=4
aY2=5
aZ2=6

;
;TABLE DE ROTATIONS
;
;			Axe	0,aX1,aY1,aZ1,aX2,aY2,aZ2
;ROT	Devient
TableDeRotations: 
aXiP:	dc.w	0,aX1,aZ1,aY2,aX2,aZ2,aY1
aXim:	dc.w	0,aX1,aZ2,aY1,aX2,aZ1,aY2
aYiP:	dc.w	0,aZ2,aY1,aX1,aZ1,aY2,aX2
aYim:	dc.w	0,aZ1,aY1,aX2,aZ2,aY2,aX1
aZiP:	dc.w	0,aY1,aX2,aZ1,aY2,aX1,aZ2
aZim:	dc.w	0,aY2,aX1,aZ1,aY1,aX2,aZ2

;
;DEFINITION DU RUBIKS
;
;objet = rubik de  26 pièces
;.piece #1
;.à
;.piece #26
;.AxeDeRotationEnCours = element de (aX1, .. , aZ2)
;.VitessDeRotation = +/- n
;.ValeurDeRotation

;piece
;.type (1 centre, 2 bord, 3 coin)
;.nbPolygones
;.polygone_1	;centre = 1 polygone (Q=6)
;.polygone_2	;bord = 2 polygones (Q=12)
;.polygone_3	;coin = 3 polygones (Q=8)
;.axeDeRotation_1 = NumAxeRot (0 si non utilisé)
;.axeDeRotation_2 = NumAxeRot (0 si non utilisé)
;.axeDeRotation_3 = NumAxeRot (0 si non utilisé)

;polygone (carre Q=56)
;.normale (x,y,z)
;.couleur (1..6)
;.pointA1 (x,y,z)
;.pointA2 (x,y,z)
;.pointB1 (x,y,z)
;.pointB2 (x,y,z)

;polygoneSauvePourRotation (Q=21)
;.normale (x,y,z)
;.couleur (1..6)
;.pointA1 (x,y,z)
;.pointA2 (x,y,z)
;.pointB1 (x,y,z)
;.pointB2 (x,y,z)

;polygoneCalcules (=nb de polygones)
;.normale (x,y,z)
;.couleur (1..6) = polygone.couleur
;.pointA1 (x,y,z)
;.pointA2 (x,y,z)
;.pointB1 (x,y,z)
;.pointB2 (x,y,z)


;***********************************************
;ALGO GENERAL
;
;Si besoin : démarrer une rotation de couronne
;	identifier les pièces concernées et faire une copie de leurs polygones
;si rotation de couronne démarrée
;	incrémenter angle rotation
;	calculer les polygones 
;Tourner la couronne selon si son axe est en rotation
;calculer (rotation ax,ay,az) les normales des faces
;garder que les faces dont les normales sont orientées vers l'observateur
;calculer les coordonnées (rotation ax,ay,az) des points
;afficher les faces de la plus loin à la plus proche de l'observateur


;***********************************************
;INITIALISER UNE ROTATION DE D'AXE 
;
;objet.AxeDeRotationEnCours = Axe de rotation à tourner =(aX1, .. , aZ2)
;	.VitessDeRotation = +/- n (incrément d'angle)
;	.ValeurDeRotation= 0
;	;sauve les polygones qui vont être impactés par la rotation
;	pour chaque Pce de Piece
;		si Pce.axeDeRotation_n = objet.AxeDeRotationEnCours alors
;			pour i=1 à pce.nbPolygones
;				polygoneSauvePourRotation = pce.polygone_n


;***********************************************
;ROTATION DE PIECE
;
;si Objet.AxeDeRotationEnCours <> 0
;	objet.ValeurDeRotation += objet.VitessDeRotation
;	
;	pour chaque pce de piece
;
;		si Objet.AxeDeRotationEnCours = pce.axeDeRotation_i alors
;			;l'objet a son axe de rotation concerné
;
;			pour chaque poly de piece.polygone_n
;				;on tourne les points dans le nouveau repère
;				poly = rot(polygoneSauvePourRotation, objet.AxeDeRotationEnCours, objet.ValeurDeRotation)
;
;			si objet.ValeurDeRotation = 90 ou -90 alors
;				;rotation terminée
;				pour chaque axe de pce.axeDeRotation_i
;					;on spécifie les nouveaux axes des pièces tournées
;					axe = TableDeRotation(objet.AxeDeRotationEnCours, axe)
;				;on met fin à la rotation en cours
;				objet.AxeDeRotationEnCours=0
;				Objet.ValeurDeRotation=0
;			fin si
;		fin si
;	fin pour
;fin si


;***********************************************
;CALCULER LES NORMALES selon angles ax, ay, az
;
;pour chaque Poly de polygones
;	polygoneCalcule.normale = rotation(poly.normale, ax, ay, az)
;	si polygoneCalcule.normale vers observateur (donc visible) alors
;		polygoneCalcule.pointAn = rotation(poly.pointAn, ax, ay, az)
;		polygoneCalcule.pointBn = rotation(poly.pointBn, ax, ay, az)
;		tracer trait(polygoneCalcule.pointA1, polygoneCalcule.pointA2, polygoneCalcule.couleur) 'en mode un point par ligne
;		tracer trait(polygoneCalcule.pointB1, polygoneCalcule.pointB2, polygoneCalcule.couleur)
;	Remplir les Polygones






*****************
** DEFINITION DU RUBIKS
*****************
; 1 Rubik
Rubiks.AxeDeRotationEnCours:	dc.w	0
Rubiks.VitessDeRotation:		dc.w	0
Rubiks.ValeurDeRotation:		dc.w	0

*****************
; 26 Pieces
;.type (1 centre, 2 bord, 3 coin)=.nbPolygones, .polygone_1, .polygone_2, .polygone_3, .axeDeRotation_1, .axeDeRotation_2, .axeDeRotation_3
PIECE:
PCE111: dc.w    3,P111aX2-POLY,P111aY2-POLY,P111aZ2-POLY, aX2,aY2,aZ2
PCE211: dc.w    2,P211aY2-POLY,P211aZ2-POLY,0, aY2,aZ2,aZ2
PCE311: dc.w    3,P311aX1-POLY,P311aY2-POLY,P311aZ2-POLY, aX1,aY2,aZ2
PCE121: dc.w    2,P121aX2-POLY,P121aZ2-POLY,0, aX2,aZ2,aZ2
PCE221: dc.w    1,P221aZ2-POLY,0,0, aZ2,aZ2,aZ2,0
PCE321: dc.w    2,P321aX1-POLY,P321aZ2-POLY,0, aX1,aZ2,aZ2
PCE131: dc.w    3,P131aX2-POLY,P131aY1-POLY,P131aZ2-POLY, aX2,aY1,aZ2
PCE231: dc.w    2,P231aY1-POLY,P231aZ2-POLY,0, aY1,aZ2,aZ2
PCE331: dc.w    3,P331aX1-POLY,P331aY1-POLY,P331aZ2-POLY, aX1,aY1,aZ2
PCE112: dc.w    2,P112aX2-POLY,P112aY2-POLY,0, aX2,aY2,aZ2
PCE212: dc.w    1,P212aY2-POLY,0,0, aY2,aY2,aZ2,0
PCE312: dc.w    2,P312aX1-POLY,P312aY2-POLY,0, aX1,aY2,aZ2
PCE122: dc.w    1,P122aX2-POLY,0,0, aX2,aY2,aZ2,0
PCE322: dc.w    1,P322aX1-POLY,0,0, aX1,aY2,aZ2,0
PCE132: dc.w    2,P132aX2-POLY,P132aY1-POLY,0, aX2,aY1,aZ2
PCE232: dc.w    1,P232aY1-POLY,0,0, aY1,aY1,aZ2,0
PCE332: dc.w    2,P332aX1-POLY,P332aY1-POLY,0, aX1,aY1,aZ2
PCE113: dc.w    3,P113aX2-POLY,P113aY2-POLY,P113aZ1-POLY, aX2,aY2,aZ1
PCE213: dc.w    2,P213aY2-POLY,P213aZ1-POLY,0, aY2,aZ1,aZ1
PCE313: dc.w    3,P313aX1-POLY,P313aY2-POLY,P313aZ1-POLY, aX1,aY2,aZ1
PCE123: dc.w    2,P123aX2-POLY,P123aZ1-POLY,0, aX2,aZ1,aZ1
PCE223: dc.w    1,P223aZ1-POLY,0,0, aZ1,aZ1,aZ1,0
PCE323: dc.w    2,P323aX1-POLY,P323aZ1-POLY,0, aX1,aZ1,aZ1
PCE133: dc.w    3,P133aX2-POLY,P133aY1-POLY,P133aZ1-POLY, aX2,aY1,aZ1
PCE233: dc.w    2,P233aY1-POLY,P233aZ1-POLY,0, aY1,aZ1,aZ1
PCE333: dc.w    3,P333aX1-POLY,P333aY1-POLY,P333aZ1-POLY, aX1,aY1,aZ1

*****************
; 54 Polygones
;.normale (x,y,z), .couleur (1..6), .pointA1 (x,y,z), .pointA2 (x,y,z), .pointB1 (x,y,z), .pointB2 (x,y,z)
POLY:
P111aX2:    dc.w    -50,0,0, 2, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
P111aY2:    dc.w    0,-50,0, 4, -50,-53,-50, -18,-53,-50, -18,-53,-18, -50,-53,-18
P111aZ2:    dc.w    0,0,-50, 6, -50,-50,-53, -18,-50,-53, -18,-18,-53, -50,-18,-53
P211aY2:    dc.w    0,-50,0, 4, -16,-53,-50, 16,-53,-50, 16,-53,-18, -16,-53,-18
P211aZ2:    dc.w    0,0,-50, 6, -16,-50,-53, 16,-50,-53, 16,-18,-53, -16,-18,-53
P311aX1:    dc.w    50,0,0, 1, 53,-50,-50, 53,-18,-50, 53,-18,-18, 53,-50,-18
P311aY2:    dc.w    0,-50,0, 4, 18,-53,-50, 50,-53,-50, 50,-53,-18, 18,-53,-18
P311aZ2:    dc.w    0,0,-50, 6, 18,-50,-53, 50,-50,-53, 50,-18,-53, 18,-18,-53
P121aX2:    dc.w    -50,0,0, 2, -53,-16,-50, -53,16,-50, -53,16,-18, -53,-16,-18
P121aZ2:    dc.w    0,0,-50, 6, -50,-16,-53, -18,-16,-53, -18,16,-53, -50,16,-53
P221aZ2:    dc.w    0,0,-50, 6, -16,-16,-53, 16,-16,-53, 16,16,-53, -16,16,-53
P321aX1:    dc.w    50,0,0, 1, 53,-16,-50, 53,16,-50, 53,16,-18, 53,-16,-18
P321aZ2:    dc.w    0,0,-50, 6, 18,-16,-53, 50,-16,-53, 50,16,-53, 18,16,-53
P131aX2:    dc.w    -50,0,0, 2, -53,18,-50, -53,50,-50, -53,50,-18, -53,18,-18
P131aY1:    dc.w    0,50,0, 3, -50,53,-50, -18,53,-50, -18,53,-18, -50,53,-18
P131aZ2:    dc.w    0,0,-50, 6, -50,18,-53, -18,18,-53, -18,50,-53, -50,50,-53
P231aY1:    dc.w    0,50,0, 3, -16,53,-50, 16,53,-50, 16,53,-18, -16,53,-18
P231aZ2:    dc.w    0,0,-50, 6, -16,18,-53, 16,18,-53, 16,50,-53, -16,50,-53
P331aX1:    dc.w    50,0,0, 1, 53,18,-50, 53,50,-50, 53,50,-18, 53,18,-18
P331aY1:    dc.w    0,50,0, 3, 18,53,-50, 50,53,-50, 50,53,-18, 18,53,-18
P331aZ2:    dc.w    0,0,-50, 6, 18,18,-53, 50,18,-53, 50,50,-53, 18,50,-53
P112aX2:    dc.w    -50,0,0, 2, -53,-50,-16, -53,-18,-16, -53,-18,16, -53,-50,16
P112aY2:    dc.w    0,-50,0, 4, -50,-53,-16, -18,-53,-16, -18,-53,16, -50,-53,16
P212aY2:    dc.w    0,-50,0, 4, -16,-53,-16, 16,-53,-16, 16,-53,16, -16,-53,16
P312aX1:    dc.w    50,0,0, 1, 53,-50,-16, 53,-18,-16, 53,-18,16, 53,-50,16
P312aY2:    dc.w    0,-50,0, 4, 18,-53,-16, 50,-53,-16, 50,-53,16, 18,-53,16
P122aX2:    dc.w    -50,0,0, 2, -53,-16,-16, -53,16,-16, -53,16,16, -53,-16,16
P322aX1:    dc.w    50,0,0, 1, 53,-16,-16, 53,16,-16, 53,16,16, 53,-16,16
P132aX2:    dc.w    -50,0,0, 2, -53,18,-16, -53,50,-16, -53,50,16, -53,18,16
P132aY1:    dc.w    0,50,0, 3, -50,53,-16, -18,53,-16, -18,53,16, -50,53,16
P232aY1:    dc.w    0,50,0, 3, -16,53,-16, 16,53,-16, 16,53,16, -16,53,16
P332aX1:    dc.w    50,0,0, 1, 53,18,-16, 53,50,-16, 53,50,16, 53,18,16
P332aY1:    dc.w    0,50,0, 3, 18,53,-16, 50,53,-16, 50,53,16, 18,53,16
P113aX2:    dc.w    -50,0,0, 2, -53,-50,18, -53,-18,18, -53,-18,50, -53,-50,50
P113aY2:    dc.w    0,-50,0, 4, -50,-53,18, -18,-53,18, -18,-53,50, -50,-53,50
P113aZ1:    dc.w    0,0,50, 5, -50,-50,53, -18,-50,53, -18,-18,53, -50,-18,53
P213aY2:    dc.w    0,-50,0, 4, -16,-53,18, 16,-53,18, 16,-53,50, -16,-53,50
P213aZ1:    dc.w    0,0,50, 5, -16,-50,53, 16,-50,53, 16,-18,53, -16,-18,53
P313aX1:    dc.w    50,0,0, 1, 53,-50,18, 53,-18,18, 53,-18,50, 53,-50,50
P313aY2:    dc.w    0,-50,0, 4, 18,-53,18, 50,-53,18, 50,-53,50, 18,-53,50
P313aZ1:    dc.w    0,0,50, 5, 18,-50,53, 50,-50,53, 50,-18,53, 18,-18,53
P123aX2:    dc.w    -50,0,0, 2, -53,-16,18, -53,16,18, -53,16,50, -53,-16,50
P123aZ1:    dc.w    0,0,50, 5, -50,-16,53, -18,-16,53, -18,16,53, -50,16,53
P223aZ1:    dc.w    0,0,50, 5, -16,-16,53, 16,-16,53, 16,16,53, -16,16,53
P323aX1:    dc.w    50,0,0, 1, 53,-16,18, 53,16,18, 53,16,50, 53,-16,50
P323aZ1:    dc.w    0,0,50, 5, 18,-16,53, 50,-16,53, 50,16,53, 18,16,53
P133aX2:    dc.w    -50,0,0, 2, -53,18,18, -53,50,18, -53,50,50, -53,18,50
P133aY1:    dc.w    0,50,0, 3, -50,53,18, -18,53,18, -18,53,50, -50,53,50
P133aZ1:    dc.w    0,0,50, 5, -50,18,53, -18,18,53, -18,50,53, -50,50,53
P233aY1:    dc.w    0,50,0, 3, -16,53,18, 16,53,18, 16,53,50, -16,53,50
P233aZ1:    dc.w    0,0,50, 5, -16,18,53, 16,18,53, 16,50,53, -16,50,53
P333aX1:    dc.w    50,0,0, 1, 53,18,18, 53,50,18, 53,50,50, 53,18,50
P333aY1:    dc.w    0,50,0, 3, 18,53,18, 50,53,18, 50,53,50, 18,53,50
P333aZ1:    dc.w    0,0,50, 5, 18,18,53, 50,18,53, 50,50,53, 18,50,53
FIN_POLY:



*****************
; 21 Polygones en sauver en cas de rotation de couronne
polygoneSauvePourRotation:
	ds.w	21*16,0
	
*****************
; 54 Polygones calculés suite rotation aX, aY, aZ
polygoneCalcules:
	;ds.b	FIN_POLY-POLY,0
	dc.w    -50,0,0, 2, -53,-50,-50, -53,-18,-50, -53,-18,-18, -53,-50,-18
    dc.w    0,-50,0, 4, -50,-53,-50, -18,-53,-50, -18,-53,-18, -50,-53,-18
    dc.w    0,0,-50, 6, -50,-50,-53, -18,-50,-53, -18,-18,-53, -50,-18,-53
    dc.w    0,-50,0, 4, -16,-53,-50, 16,-53,-50, 16,-53,-18, -16,-53,-18
    dc.w    0,0,-50, 6, -16,-50,-53, 16,-50,-53, 16,-18,-53, -16,-18,-53
    dc.w    50,0,0, 1, 53,-50,-50, 53,-18,-50, 53,-18,-18, 53,-50,-18
    dc.w    0,-50,0, 4, 18,-53,-50, 50,-53,-50, 50,-53,-18, 18,-53,-18
    dc.w    0,0,-50, 6, 18,-50,-53, 50,-50,-53, 50,-18,-53, 18,-18,-53
    dc.w    -50,0,0, 2, -53,-16,-50, -53,16,-50, -53,16,-18, -53,-16,-18
    dc.w    0,0,-50, 6, -50,-16,-53, -18,-16,-53, -18,16,-53, -50,16,-53
    dc.w    0,0,-50, 6, -16,-16,-53, 16,-16,-53, 16,16,-53, -16,16,-53
    dc.w    50,0,0, 1, 53,-16,-50, 53,16,-50, 53,16,-18, 53,-16,-18
    dc.w    0,0,-50, 6, 18,-16,-53, 50,-16,-53, 50,16,-53, 18,16,-53
    dc.w    -50,0,0, 2, -53,18,-50, -53,50,-50, -53,50,-18, -53,18,-18
    dc.w    0,50,0, 3, -50,53,-50, -18,53,-50, -18,53,-18, -50,53,-18
    dc.w    0,0,-50, 6, -50,18,-53, -18,18,-53, -18,50,-53, -50,50,-53
    dc.w    0,50,0, 3, -16,53,-50, 16,53,-50, 16,53,-18, -16,53,-18
    dc.w    0,0,-50, 6, -16,18,-53, 16,18,-53, 16,50,-53, -16,50,-53
    dc.w    50,0,0, 1, 53,18,-50, 53,50,-50, 53,50,-18, 53,18,-18
    dc.w    0,50,0, 3, 18,53,-50, 50,53,-50, 50,53,-18, 18,53,-18
    dc.w    0,0,-50, 6, 18,18,-53, 50,18,-53, 50,50,-53, 18,50,-53
    dc.w    -50,0,0, 2, -53,-50,-16, -53,-18,-16, -53,-18,16, -53,-50,16
    dc.w    0,-50,0, 4, -50,-53,-16, -18,-53,-16, -18,-53,16, -50,-53,16
    dc.w    0,-50,0, 4, -16,-53,-16, 16,-53,-16, 16,-53,16, -16,-53,16
    dc.w    50,0,0, 1, 53,-50,-16, 53,-18,-16, 53,-18,16, 53,-50,16
    dc.w    0,-50,0, 4, 18,-53,-16, 50,-53,-16, 50,-53,16, 18,-53,16
    dc.w    -50,0,0, 2, -53,-16,-16, -53,16,-16, -53,16,16, -53,-16,16
    dc.w    50,0,0, 1, 53,-16,-16, 53,16,-16, 53,16,16, 53,-16,16
    dc.w    -50,0,0, 2, -53,18,-16, -53,50,-16, -53,50,16, -53,18,16
    dc.w    0,50,0, 3, -50,53,-16, -18,53,-16, -18,53,16, -50,53,16
    dc.w    0,50,0, 3, -16,53,-16, 16,53,-16, 16,53,16, -16,53,16
    dc.w    50,0,0, 1, 53,18,-16, 53,50,-16, 53,50,16, 53,18,16
    dc.w    0,50,0, 3, 18,53,-16, 50,53,-16, 50,53,16, 18,53,16
    dc.w    -50,0,0, 2, -53,-50,18, -53,-18,18, -53,-18,50, -53,-50,50
    dc.w    0,-50,0, 4, -50,-53,18, -18,-53,18, -18,-53,50, -50,-53,50
    dc.w    0,0,50, 5, -50,-50,53, -18,-50,53, -18,-18,53, -50,-18,53
    dc.w    0,-50,0, 4, -16,-53,18, 16,-53,18, 16,-53,50, -16,-53,50
    dc.w    0,0,50, 5, -16,-50,53, 16,-50,53, 16,-18,53, -16,-18,53
    dc.w    50,0,0, 1, 53,-50,18, 53,-18,18, 53,-18,50, 53,-50,50
    dc.w    0,-50,0, 4, 18,-53,18, 50,-53,18, 50,-53,50, 18,-53,50
    dc.w    0,0,50, 5, 18,-50,53, 50,-50,53, 50,-18,53, 18,-18,53
    dc.w    -50,0,0, 2, -53,-16,18, -53,16,18, -53,16,50, -53,-16,50
    dc.w    0,0,50, 5, -50,-16,53, -18,-16,53, -18,16,53, -50,16,53
    dc.w    0,0,50, 5, -16,-16,53, 16,-16,53, 16,16,53, -16,16,53
    dc.w    50,0,0, 1, 53,-16,18, 53,16,18, 53,16,50, 53,-16,50
    dc.w    0,0,50, 5, 18,-16,53, 50,-16,53, 50,16,53, 18,16,53
    dc.w    -50,0,0, 2, -53,18,18, -53,50,18, -53,50,50, -53,18,50
    dc.w    0,50,0, 3, -50,53,18, -18,53,18, -18,53,50, -50,53,50
    dc.w    0,0,50, 5, -50,18,53, -18,18,53, -18,50,53, -50,50,53
    dc.w    0,50,0, 3, -16,53,18, 16,53,18, 16,53,50, -16,53,50
    dc.w    0,0,50, 5, -16,18,53, 16,18,53, 16,50,53, -16,50,53
    dc.w    50,0,0, 1, 53,18,18, 53,50,18, 53,50,50, 53,18,50
	dc.w    0,50,0, 3, 18,53,18, 50,53,18, 50,53,50, 18,53,50
	dc.w    0,0,50, 5, 18,18,53, 50,18,53, 50,50,53, 18,50,53
*****************
