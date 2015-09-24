#!/bin/bash
#############################################################################################
#                                                                                           #
# Aquest script configura via consola els paràmetres de connexió de les unitats compartides #
# del servidor de centre (Linkat edu)                                                       #
#                                                                                           #
# Llicència: GPL v3.0                                                                       #
# Autor: Joan de Gracia. Servei TAC. Departament d'Ensenyament. Generalitat de Catalunya.   #
# Modificat per Tomàs Sanchez i Pablo Vigo                                                  #
# Versió per consola per Aleix Quintana Alsius                                              #
# Versió: 1.0                                                                               #
# Data: 26-07-2013                                                                          #
#############################################################################################
busca_unitat(){
    UNITATS=(${UNITATS//,/ })
    disk=$(echo $1|tr '[:lower:]' '[:upper:]')
    for unitat in "${UNITATS[@]}"
    do
        unitat_up=$(echo ${unitat#*@}|tr '[:lower:]' '[:upper:]')
        if [ "$unitat_up" = $disk ]
        then
            echo ${unitat} ; #usem la unitat preconfigurada
        fi
    done
}


usage() { 
    echo  "${BOLD}Muntador d'unitats en xarxa${NORM}. Opcions:"
    echo -e "\t-s \t\tSilenci. No preguntis per usuaris ni per unitats a muntar. (en cas de servidor de window 2010 o 2003 preguntarà [TODO] )"
    echo -e "\t-d \"u:c@d\"\tDiscs a muntar, amb les credencials (u->usuari,c->contrassenya,d->disc)"
    echo -e "\t\t\tformat: ${BOLD}-d \"usuari:contrassenya@NomDeDiscALaXarxa,2nusuari:2contrassenya@NomDUnAltreDiscALaXarxa\"${NORM} p.ex: gestio:ge2t10@Gestio "
    echo -e "\t-i IP\t\tIp del servidor"
    echo -e "\t-w \t\tWindows. El servidor es tracta d'un servidor Windows Server 2003 o Windows Server 2010."
    echo ""
    echo "Exemple: sudo ./muntador-unitats-cli.sh -i 192.168.0.100 -d  \"prof:passw@Professorat,gestio:passw@Gestio,argo:passw@Treball,super:passw@programari\" -s"
    echo ""
    echo "En cas de voler desfer les accions realitzades per l'script s'ha d'esborrar la carpeta /mnt/Servidor, el fitxer /etc/auto.muntador i els continguts de /etc/auto.master"
    exit 1; 
}
acaba() {
    rm $FITXER_TMP $FITXER_RECURSOS $DIALOG_TMP
    rm -rf $DIR_TMP
}


#Set fonts for Help.
NORM=`tput sgr0`
BOLD=`tput bold`
REV=`tput smso`

LINUX_SERVER=0 #0=TRUE 1=FALSE
while getopts ":swd:i:" opt; do
  case $opt in
    s)
      echo "-s activat" >&2
      NOMOLESTIS=0
      ;;
    d)
      echo "-d activat, Parametre: $OPTARG" >&2
      UNITATS=$OPTARG
      ;;
    i)
      echo "-i activat, Parametre: $OPTARG" >&2
      IP=$OPTARG
      ;;
    w)
      echo "-w activat, es tracta d'un servidor Windows Server 2003 o Windows Server 2010."
      LINUX_SERVER=1
      ;;
    \?)
      echo "Opció invàlida: -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
    :)
      echo "L'opció -$OPTARG requereix un argument." >&2
      usage >&2
      exit 1
      ;;      
  esac
done

if [[ $NOMOLESTIS ]] 
then
    [ -z ${IP+x} ] || [ -z ${UNITATS+x} ]  && echo "no estan definits la IP o les unitats" && usage && exit 1
fi

if [ -n "$(id | grep root)" ]; then

{
#
# Es comprova que la distribució base sigui Linkat edu/Ubuntu LTS
#
	LSB=/etc/lsb-release
	if [ -e $LSB ]; then
		if [  "$(grep -i ubuntu $LSB)" = "" ]; then
			echo "Sembla que la distribució no sigui Linkat edu.\n\n S'avorta el programa."; 
			exit 1
		fi
	fi
#
# Es comprova que l'script no ha estat executat anteriorment.
#
	if [ -e /etc/muntador_unitats ]; then
		if [[ ! $NOMOLESTIS ]]; then
			dialog --title "Connexió d'unitats de xarxa" --yesno "El configurador ja ha estat aplicat.\n\n Voleu tornar a aplicar-ho?" 30 90
		else
			echo "tornant a executar el configurador"
		fi
		if [ "$?" != 0 ] ; then
			exit 1
		else
			mv /etc/auto.muntador /etc/Linkat/linkat-muntador-unitats/auto.muntador.$(date +%F)
			[ `grep -c "/mnt\/Servidor     \/etc\/auto.muntador --timeout=60 --ghost" /etc/auto.master` == 0 ] && \ 
			echo "${BOLD}Pas 0:${NORM}escribint continguts a /etc/auto.master i creant directori /mnt/Servidor" && \
			echo "/mnt/Servidor     /etc/auto.muntador --timeout=60 --ghost" >> /etc/auto.master && \
			mkdir -p /mnt/Servidor
		fi
	else
                echo "${BOLD}Pas 0:${NORM}escribint continguts a /etc/auto.master i creant directori /mnt/Servidor"
		echo "/mnt/Servidor     /etc/auto.muntador --timeout=60 --ghost" >> /etc/auto.master	
		mkdir -p /mnt/Servidor
	fi

#
# Aturem el servei autofs
#
if service --status-all | grep -Fq 'autofs'; then         
        service autofs stop
else
        echo "no autofs service present";
        exit 1
fi
	

#
# RESPOSTA: Aquesta variable s'utilitza per confirmar que la configuració introduïda és correcta.
# NO es realitza cap actuació fins que l'usuari ho confirma.
#
	RESPOSTA=""
	while [ "$RESPOSTA" = "" ]
	do
#
# DIR_TMP: Directori que conté els fitxers de credencials de cadascun dels usuaris del servidor.
# Es tracta d'un directori temporal que s'elimina al final de l'execució de l'script.
#
		DIR_TMP=$(mktemp -d)
#
# FITXER_TMP: Conté la sintaxi per fer el muntatge de les unitats dins del fitxer /etc/auto.muntador.
# Es tracta d'un fitxer temporal que s'elimina al final de l'execució de l'script.
#
		FITXER_TMP=$(mktemp)
		

# FITXER TMP  DIALEG: Conté les variables que vagi emmagatezemant el programa dialog
                DIALOG_TMP=$(mktemp)
#
# FITXER_RECURSOS: Conté el nom dels recursos detectats al servidor de centre.
# Es tracta d'un fitxer temporal que s'elimina al final de l'execució de l'script.
#
		FITXER_RECURSOS=$(mktemp)

		
		
		#IP=""
		
		while [ "$IP" = "" ]; do
			dialog --title "Introduïu la IP del servidor de centre" --inputbox "Introduïu la IP del servidor del centre" 30 90 2> $DIALOG_TMP
			IP=$(<$DIALOG_TMP)
		if [ "$?" = "1" ] ; then
			echo "Configuració cancel·lada"
			acaba
			exit 1
		fi

		done


		RECURSOS="$(smbclient -L $IP -g -N 2>/dev/null|grep -i ^disk|awk -F '|' '{print $2}')"


# Comprovem si el servidor necessita usuari i contrasenya i mostrem les unitats compartides

        if [ $LINUX_SERVER -gt 0 ];then
                dialog --title "Sistema operatiu del Servidor de centre"  --yesno "Els Windows Server 2003 i Windows    Server 2010 necessiten un usuari i una contrasenya per mostrar les unitats compartides.\n\nSi el vostre servidor és una Linkat, Linux o una altra versió de Windows, no cal que introduïu cap usuari.\n\n Voleu introduir un usuari i contrasenya per veure les unitats compartides?" 30 90
                if [ $? -gt 0 ] ; then
                        LINUX_SERVER=1
                else
                        LINUX_SERVER=0
                fi
        fi

		if [ $LINUX_SERVER -eq 0 ] ; then
                        OPTS=$(smbclient -g -N -L $IP 2> /dev/null | grep ^Disk | perl -ne 'chomp; @ary = split(m/\|/, $_); print "$ary[1] \"$ary[2]\" on ";') 
                        OPTS_NOMOLESTIS=$(smbclient -g -N -L $IP 2> /dev/null | grep ^Disk | perl -ne 'chomp; @ary = split(m/\|/, $_); print "$ary[1] ";') 
                else
			USUARIWIN=$(dialog --title "Usuari" --inputbox "Introduïu l'usuari per al servidor"  30 90 --stdout)
			PASSWDWIN=$(dialog --title "Contrassenya" --inputbox "Introduïu la contrassenya per al servidor"  30 90 --stdout)
			
			if [ "$USUARIWIN" = "" -o "$PASSWDWIN" = "" ] ;then
                                echo "S'ha produït un error."
                                acaba
                                exit 1;
                        fi
                                
			OPTS="$(smbclient -g -N -L $IP -U $USUARIWIN%$PASSWDWIN 2> /dev/null | \
			grep ^Disk | \
                        perl -ne 'chomp; @ary = split(m/\|/, $_); print "$ary[1] \"$ary[2]\" on ";' )"       
                fi
                    
                      
                if [[ ${#OPTS} -gt 0 ]]
                then
                    if [[ $NOMOLESTIS ]]
                    then
                        ret="${OPTS_NOMOLESTIS}" 
                    else
                        ret="$(dialog --title "Seleccioneu unitats a muntar" \
                                --checklist  "Unitats compartides al servidor $IP"  80 40 20 $OPTS\
                        --stdout)" 
                        if [ "$?" = 1 ] ; then
                                echo "Configuració cancel·lada"
                                acaba
                                exit 1
                        fi
                    fi
                fi



echo "Unitat de xarxa : Usuari" >> $FITXER_RECURSOS
echo "========================" >> $FITXER_RECURSOS

[[ ! $NOMOLESTIS ]] && dialog  --title "Crear usuaris a l'ordinador" --msgbox "Els usuaris que s'introduexin tot seguit es crearan en aquest ordinador.\n\nAquests usuaris han d'existir al servidor $IP per realitzar la connexió.\n\nAfegiu l'usuari i la contrasenya per connectar amb cadascuna de les diferents unitats de xarxa del servidor $IP.\n\nPer exemple:\n\nRecurs: professorat\nUsuari: prof\n\nRecurs: treball\nUsuari: argo" 30 90

		for share in $(echo $ret);
		do
                        UNITAT_TROBADA=$(busca_unitat "$share")
                        if [ "$UNITAT_TROBADA" != "" ]
                        then
                            share=${UNITAT_TROBADA#*@}
                            USUARI=${UNITAT_TROBADA%%:*}
                            CONTRASENYA=$(echo ${UNITAT_TROBADA#*:} |  sed 's/\(.*\)@.*/\1/')
                        else
                            if [[ ! $NOMOLESTIS ]]
                            then
                                USUARI=""
                                while [ "$USUARI" = "" ]
                                do
                                    USUARI=$(dialog --title "Usuari" --inputbox "Introduïu l'usuari per a la unitat $share"  30 90 --stdout)
                                    CONTRASENYA=$(dialog --title "Contrassenya" --inputbox "Introduïu la contrassenya per a la unitat $share"  30 90 --stdout)
                                    
                                    if [ "$USUARI" = "" || "$CONTRASENYA" = "" ] ;then
                                            echo "S'ha produït un error."
                                            acaba
                                            exit 1;
                                    fi
                                done
                            else
                                #NOMOLESTIS SET: NO INCLOURE UNITAT
                                continue
                            fi
                        fi

			RECURS1=$(echo $share|tr '[:lower:]' '[:upper:]')
			case $RECURS1 in
			S)
				PERMISOS_FITXERS="0664"
				PERMISOS_DIRECTORIS="0775"
			;;
			PROGRAMARI)
				PERMISOS_FITXERS="0664"
				PERMISOS_DIRECTORIS="0775"
			;;
			T)
				PERMISOS_FITXERS="0666"
				PERMISOS_DIRECTORIS="0777"
			;;
			TREBALL)
				PERMISOS_FITXERS="0666"
				PERMISOS_DIRECTORIS="0777"
			;;
			*)
				PERMISOS_FITXERS="0660"
				PERMISOS_DIRECTORIS="0770"
			;;
			esac
			printf "$share -fstype=cifs,credentials=/etc/samba/credentials_$USUARI,uid=$USUARI,gid=$USUARI,iocharset=utf8,file_mode=$PERMISOS_FITXERS,dir_mode=$PERMISOS_DIRECTORIS ://$IP/$share\n" >> $FITXER_TMP 	
			printf "username=$USUARI\npassword"="$CONTRASENYA\n" > $DIR_TMP/credentials_$USUARI
			echo "$share : $USUARI" >> $FITXER_RECURSOS
		done
		

		if [[ ! $NOMOLESTIS ]] 
		then
                    dialog --title "Confirmació de la configuració" --yesno "$(<$FITXER_RECURSOS)" \
			 30 90 
                    if [ "$?" = 1 ] ; then
                            echo "Configuració cancel·lada"
                            RESPOSTA=""
    #
    # Eliminació dels fitxers/directoris temporals
    # En cas de cancel·lació de l'aplicatiu per part de l'usuari, els fitxers/directoris temporals
    # s'eliminen perquè no interfereixi la informació errònia amb la correcta.
    #
                            acaba 
                            exit 1;
                    else
                            RESPOSTA="1"
                            cp $FITXER_TMP /etc/auto.muntador
                    fi
                else
                    RESPOSTA="1"
                    cp $FITXER_TMP /etc/auto.muntador
                fi
	done

	
for i in $(ls $DIR_TMP | grep -i credentials)
do
    echo $(grep -i username $DIR_TMP/$i | awk -F '=' '{print $2}')
    echo $(grep -i password $DIR_TMP/$i | awk -F '=' '{print $2}')
done
#
# Canvi permisos dels fitxers credentials
#
        echo "${BOLD}Pas 1:${NORM}escribint credencials samba pertinents al directori /etc/samba/ i canviant-ne els permisos"
	cp $DIR_TMP/credentials* /etc/samba/
	chmod 640 /etc/samba/credentials*
	chown root:root /etc/samba/credentials*
#
# Creació d'usuaris. S'obtenen dels fitxers "credentials"
# S'accepta que els usuaris puguin tenir contrasenya en blanc
# Els usuaris es creen al directori /home-local
#    
        echo "${BOLD}Pas 2:${NORM} Creant usuaris que no existeixen en local"
	USUARI=""
	CONTRASENYA=""
	HOME_LOCAL="/home-local"
	if [ ! -d $HOME_LOCAL ]; then
		mkdir -p $HOME_LOCAL
	fi
	for i in $(ls $DIR_TMP | grep -i credentials)
	do
		USUARI=$(grep -i username $DIR_TMP/$i | awk -F '=' '{print $2}')
		CONTRASENYA=$(grep -i password $DIR_TMP/$i | awk -F '=' '{print $2}')
		if [ "$CONTRASENYA" = "" ]; then
			CONTRASENYA_XIFRADA=""
		else
			CONTRASENYA_XIFRADA="$(mkpasswd $CONTRASENYA)"
		fi

# Es comprova que l'usuari no existeixi ja al sistema
#
		if [ "$(id $USUARI 2>/dev/null)" = "" ];
		then
			useradd -c "Usuari $USUARI" -s /bin/bash -d $HOME_LOCAL/$USUARI -m -p "$CONTRASENYA_XIFRADA" $USUARI
		fi
		echo "${BOLD}Pas 3:${NORM} Afegint enllaços a l'Escriptori de cada usuari"
		if [[ -d /home/$USUARI ]];  then  
			mkdir -m 755 -p /home/$USUARI/Escriptori/
			chown $USUARI:$USUARI /home/$USUARI/Escriptori/
		fi
		if [[ -d /home-local/$USUARI ]];  then  
			mkdir -m 755 -p /home-local/$USUARI/Escriptori/
			chown $USUARI:$USUARI /home-local/$USUARI/Escriptori/
		fi
		ln -s /mnt/Servidor /home/$USUARI/Escriptori/Unitats\ xarxa
		ln -s /mnt/Servidor /home-local/$USUARI/Escriptori/Unitats\ xarxa
	done

#
# Es crea el fitxer muntador_unitats que serveix per detectar si l'script ha estat executat o no.
# Es munten les unitats del servidor en acabar l'execució de l'script.
#
        echo "${BOLD}Pas 4:${NORM} Es crea el fitxer muntador_unitats que serveix per detectar si l'script ha estat executat o no"
        touch /etc/muntador_unitats
        echo "${BOLD}Pas 5:${NORM} Reiniciem el servei autofs"
	service autofs start
#
# Eliminació dels fitxers/directoris temporals
#
	acaba
	echo "Procés finalitzat amb èxit."
}
else
	echo "No sou usuari root i no podeu executar el programa"
	exit 1
fi
