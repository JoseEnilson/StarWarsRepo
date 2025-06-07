#!/usr/bin/env bash
LANG=C
#
# adicao-disco-v1.0.sh - Adição, remoção e redimensionamento de discos no sistema
#
# Autor:      José Enilson Mota Silva
# Manutenção: José Enilson Mota Silva
#
# ------------------------------------------------------------------------ #
#  Este programa irá adicionar, remover e redimensionar os discos do sistema
#
#  Exemplo de execução (executar como root):
#      # ./disk-v1-4.sh
#
#-----------------PACKAGE REQUIRED ----------------------------------------#
# - bc.x86_64
# - cloud-utils-growpart.x86_64
# ------------------------------------------------------------------------ #
# Histórico de versionamento:
#
#   v1.0 29/09/2024:
#       - Adicionar um disco ao sistema
#   v1.1 02/10/2024:
#       - Remover um disco que tem volumes associados
#       - Remover um disco que não tem volumes associados
#   v1.2 06/10/2024
#       - Redimensionar disco
#   v1.3 06/11/2024
#       - Adicionar arquivo de logs
#   v1.4 24/11/2024
#       - Mostrar barra de progresso
#   v1.7 08/12/2024
#       - Adicionar disco a um grupo de volume
# ------------------------------------------------------------------------ #
# Testado em:
#   GNU bash, version 5.2.15(1)-release (x86_64-pc-linux-gnu)
#       Debian GNU/Linux 12 (bookworm)
#       CentOS Linux 7 (Core) |  Kernel: Linux 3.10.0-1160.24.1.el7.x86_64
#
#       Oracle Linux 7.9 | Oracle Linux 9.3
#--------------------------- HOMOLOGADO EM ---------------------------------#
#
#  HOST      REQUISIÇÃO  PROCEDIMENTO
#
#  HBES873   15365250    REDIMENSAO DE DISCO
#  HBES1522  15369901    REDIMENSAO DE DISCO
#  HBES252   15501145    ADICAO DE DISCO / PARTICAO
# ------------------------------- VARIAVEIS ------------------------------ #

DISKSFORMAT=$(lsblk | grep -o "sd[a-z]" | uniq -d)
DISKS=$(lsblk | grep -w "sd." | cut -d" " -f 1)
DISKAVAILABLE=$(echo "$DISKSFORMAT $DISKS" | tr ' ' '\n' | sort | uniq -u)
BAR_SIZE=40
BAR_CHAR_DONE="#"
BAR_CHAR_TODO="-"
BAR_PERCENTAGE_SCALE=2
PART_NUM=1
#-------------------------------- FUNCTIONS --------------------------------#

function scanNewDisk() {
   scsi=$(ls /sys/class/scsi_host/) && for dev in $scsi; do $(echo "- - -" >/sys/class/scsi_host/$dev/scan); done
}

function rescanDisk() {
   scsidev=$(ls /sys/class/scsi_device/) && for dev in $scsidev; do $(echo "1" >/sys/class/scsi_device/$dev/device/rescan); done
}

function sucesso() {
   echo -e "\n\n  \033[1;32m         ***** CONFIGURACAO EXECUTADA COM SUCESSO *****\033[0m \n\n"
   echo -e "---------------------------- \n\033[1;33m  << DF -HT >> \033[0m\n"
   df -hT
   echo -e "\n\n----------------------------- \n\033[1;33m << FSTAB >>\033[0m"
   cat /etc/fstab
   echo -e "\n\n----------------------------- \n\033[1;33m << LSBLK >> \033[0m\n"
   lsblk
   echo -e "\n\n"
}

function erro () {
    echo -e "\n\n\033[0;31m    ERRO AO APLICAR AS CONFIGURACOES!!!\033[0m"
    echo -e "\033[0;31m    CONSULTE OS ARQUIVOS DE LOGS: lvm.log e/ou disk<data>.log\033[0m\n\n"
    exit
}

function show_progress {
   current="$1"
   total="$2"

   # calculate the progress in percentage
   percent=$(bc <<<"scale=$BAR_PERCENTAGE_SCALE; 100 * $current / $total")
   # The number of done and todo characters
   done=$(bc <<<"scale=0; $BAR_SIZE * $percent / 100")
   todo=$(bc <<<"scale=0; $BAR_SIZE - $done")

   # build the done and todo sub-bars
   done_sub_bar=$(printf "%${done}s" | tr " " "${BAR_CHAR_DONE}")
   todo_sub_bar=$(printf "%${todo}s" | tr " " "${BAR_CHAR_TODO}")

   # output the bar
   echo -ne "\rProgress : [${done_sub_bar}${todo_sub_bar}] ${percent}%"

   if [ $total -eq $current ]; then
      echo -e "\nDONE"
   fi
}

function call_show_progress_bar() {
   rpm -q bc > /dev/null
   #bcPacote=$(whereis bc) && bcPacoteByte=$(echo "$bcPacote" | wc -c)
   if [ "$?" -eq 1 ]; then
      echo "     DISCOS SENDO ESCANEADOS. AGUARDE ...."
      sleep 7
   else
      echo -e "\n            DISCOS SENDO ESCANEADOS. AGUARDE ...\n"
      tasks_in_total=40
      for current_task in $(seq $tasks_in_total); do
        sleep 0.2
        show_progress $current_task $tasks_in_total
      done
   fi
}

function discosDisponiveis() {
        if [ -z "$DISKAVAILABLE" ]; then
            echo -e "\n\033[0;31m    NÃO HÁ DISCOS PARA SEREM PARTICIONADOS\033[0m\n"
            echo "Caso o disco já esteja particionado, tecle ENTER e \"AGUARDE...\" ou CTRL + C para encerrar."
            read -p " "
            lsblk
            echo " "
            read -p "INFORME O DISCO [ sdx ]: " disk
        else
            echo -e "\n  \033[1;34m DISCOS DISPONIVEIS PARA PARTICIONAMENTOS: \n\033[0m"
            lsblk | egrep -w "$(echo "$DISKSFORMAT $DISKS" | tr ' ' '\n' | sort | uniq -u)"
            echo " "
            read -p "INFORME O DISCO [ sdx ]: " disk
            discoExist=$(lsblk | grep -o sd[a-z] | grep -i "$disk") # verifica se o disco exite
            test -z "$discoExist" && erro && exit
            discoList=$(echo "$DISKAVAILABLE" | grep -i $disk) # Verifica se o disco informado está disponível
            test -z "$discoList" && erro && exit
            instrucoesFSDISK # function
            pvcreate /dev/$disk$PART_NUM >> lvm.log
            if [ "$?" -eq 5 ]; then
                erro
            #else
            #    echo " "
            fi
        fi

}

function adicionarDisco() {
   read -p "INFORME O NOME DO VOLUME GROUP [vg_NOME]: " vg
   vgcreate $vg /dev/$disk$PART_NUM >>lvm.log

   # testa se o disco informado não existe ou se já está configurado. Case "true", sai do programa.
   test $? -eq 5 && erro && exit

   read -p "INFORME O NOME DO LOGICAL VOLUME [lv_NOME]: " lv
   lvcreate -l 100%FREE -n $lv $vg >>lvm.log
   mkfs.ext4 /dev/$vg/$lv >>lvm.log

   test $? -ne 0 && erro && exit

   read -p "INFORME UM PONTO DE MONTAGEM (SE NAO EXISTIR SERA CRIADO) [ /ponto ] : " ponto
   mkdir -p $ponto
   mount /dev/$vg/$lv $ponto
   persisttab=$(df -hT | grep -i "$lv" | tr -s " " | cut -d" " -f 1)
   echo "$persisttab $ponto ext4 defaults 1 2" >>/etc/fstab
   logs >>disk$(date +%Y%m%d).log # function
}

function redimensionar() {
   echo -e "\n---------------------------------------\n"
   lv=$(lsblk | grep -A1 -B1 $disk | tail -n 1 | awk '{print $1}' | cut -d"-" -f 2)
   pvresize "$partition" >>lvm.log
   lvolume=$(lvdisplay | grep -i path | awk '{print $NF}' | grep -i $lv)
   lvextend -l +100%free $lvolume >>lvm.log
   test $? -eq 5 && erro && exit
   resize2fs $lvolume >>lvm.log
   sucesso # function
}

function remover() {
   #echo -e "\n-----------------------------\n"
   lvchange -an /dev/$volumes >>lvm.log
   lvremove /dev/$volumes >>lvm.log
   vgchange -an $vg >>lvm.log
   vgremove $vg >>lvm.log
   pvremove /dev/"$disk$PART_NUM" >>lvm.log

   test $? -ne 0 && erro && exit

   echo 1 >/sys/block/$disk/device/delete
   remEntradaFstab=$(echo $volumes | sed 's/\//-/')
   sed -i "/$remEntradaFstab/d" /etc/fstab
   sucesso
   #echo -e "\n-----------------------------\n"
   logs >>disk$(date +%Y%m%d).log # function
}

instrucoesFSDISK() {
   echo -e "\n\n            PARTICIONE O DISCO!!!"
   echo -e "\n\n\033[1;33m  CASO O DISCO JÁ ESTEJA PARTICIONADO, DIGITE q e ENTER para sair.\033[0m"
   echo -e "\n\n\033[1;33m  Instrucoes abaixo: \033[0m\n"
   echo -e "\033[1;33m 1) Digite n e tecle ENTER 5 vezes;\033[0m"
   echo -e "\033[1;33m 2) Digite t para escolher o tipo de sistema e tecle ENTER;\033[0m"
   echo -e "\033[1;33m 3) Digite o código -> 8e, e tecle ENTER\033[0m"
   echo -e "\033[1;33m 4) Digite w e depois ENTER para sair e salvar.\033[0m\n"
   fdisk /dev/$disk
}

function logs() {
   echo -e " [ $(date) ]\n\n"
   echo -e "               << LSBLK >>"
   echo -e "\n$(lsblk)"
   echo -e "\n-----------------------------------------------\n"
   echo -e "               << DF -HT >>"
   echo -e "\n$(df -hT)\n"
   echo -e "\n-----------------------------------------------\n"
   echo -e "               << FSTAB >>"
   echo -e "\n$(cat /etc/fstab)\n"
   echo -e "\n***********************************************"
   echo -e "|=============================================|"
   echo -e "***********************************************"
}
# ------------------------------- EXECUCAO ------------------------------- #

echo -e "\nESCOLHA\n"
echo "1 - Adicionar um disco ao sistema"
echo "2 - Remover um disco que tenha volumes associados"
echo "3 - Adicionar um disco a um grupo de volume"
echo "4 - Redimensionar um disco"
echo "5 - Sair do programa"
echo " "

read -p "INFORME UM NUMERO: " NUM

if [ -z "$NUM" ]; then

   echo -e "\n\033[0;31m NENHUM VALOR INFORMADO. PROGRAMA ENCERRADO\033[0m\n"
   exit
else
    if [ "$NUM" -eq 1 ]; then
        # funcao que escaneia todos os discos do sistema
        scanNewDisk &
        # funcao que coleta os logs e salva em um arquivo com a data do dia
        logs >> disk$(date +%Y%m%d).log
        # funcao que chama a barra de progresso
        call_show_progress_bar
        # funcao que lista os discos disponíveis para serem particionados
        discosDisponiveis
        # funcao que contem as configurações de volumes e sistema de arquivos para o disco
        adicionarDisco
        # funcao que imprimi uma mensagem na tela se a configuração for executada com sucesso
        sucesso
   elif [ "$NUM" -eq 2 ]; then
      logs >>disk$(date +%Y%m%d).log
      echo -e "\n$(lsblk)"
      echo -e "\n\033[1;33m    ATENCAO!!! -> ACAO IRREVERSIVEL \033[0m"
      read -p "    INFORME O DISCO QUE SERÁ REMOVIDO [Exemplo: sda ]? " disk

      # Se não for informado um valor, o script será encerrado.
      test -z "$disk" && erro && exit

      discoExist=$(lsblk | grep -o sd[a-z] | grep -i "$disk")

      # Se o disco não existir o script será encerrado
      test -z "$discoExist" && erro && exit

      vg=$(pvs | grep -i $disk$PART_NUM | awk '{print $2}')

      lv=$(lvs | grep -i "$vg" | awk '{print $1}')
      volumes=$(echo $vg/$lv)

      test -z $vg && erro && exit
      test -z "$volumes" && erro && exit

      # A variável abaixo informa quantas discos estão associados ao mesmo grupo de volume.
      countVg=$(pvs | grep -i $vg | wc -l)
      #-----------------------------------------------------------------------------------------------#
        # Se o grupo de volume tiver mais de 1 disco configurado, o script irá se encerrar.
        if [ $countVg -gt 1 ]; then
            echo -e "\n\n\033[0;31m    GRUPO DE VOLUME COM MAIS DE UM DISCO CONFIGURADO.\033[0m"
            echo -e "\033[0;31m          FAÇA A REMOCAO DO DISCO MANUALMENTE!!!\033[0m\n\n"
            echo -e " SUGESTOES\n\n"
            echo -e " Metodo - 1\n"
            echo " - Aumentar o tamanho de um dos discos do grupo."
            echo " - Usar o comando growpart /dev/sdx 1"
            echo " - Usar o comando pvmove para mover os dados para o espaço free."
            echo " - Usar o vgreduce no disco que será removido"
            echo " - Remover o disco (vgremove /dev/sdx1)"
            echo -e "\n---------------------\n"
            echo -e " Metodo - 2\n"
            echo " - Inserir um novo disco ao grupo de volume"
            echo " - Usar o  growpart"
            echo " - Preparar o disco com fsdisk"
            echo " - Usar o comando pvcreate"
            echo " - Usar o comando vgextend para estender o grupo"
            echo " - Usar o comando pvmove para mover os dados para o espaço free."
            echo " - Usar o vgreduce no disco que será removido"
            echo " - Remover o disco (vgremove /dev/sdx1)"
            echo -e "\n----------------\n"
            echo -e " Metodo - 3\n"
            echo " - Migrar os dados para outro disco."
            echo " - Remover o disco desejado"
            echo " - Refaz o grupo de volume"
            echo " - Mover os dados para o grupo de volume refeito."
            echo  -e " - Remover o disco inserido somente para esse fim.\n"
            exit
        fi

      #-----------------------------------------------------------------------------------------------#
      mountPoint=$(lsblk | grep -iA1 $disk$PART_NUM | grep -i "$vg-$lv" | awk '{print $7}')
      test -n $mountPoint && umount $mountPoint & >> disk$(date +%Y%m%d).log

      # Se ocorrer erro na desmontagem do disco, o script será encerrado.
      test $? -ne 0 && erro && exit

      remover # function

   elif [ "$NUM" -eq 3 ]; then
      logs >>disk$(date +%Y%m%d).log # function
      # funcao que escaneia os discos
      scanNewDisk &
      # funcao que chama a barra de progresso
      call_show_progress_bar

      # funcao que lista os discos disponíveis para serem particionados
      discosDisponiveis
      echo " "

      vg=$(pvs | grep -i $disk$PART_NUM | awk '{print $2}')

      # funcao que auxilia na configuracao do disco.
      instrucoesFSDISK

      echo -e "\n$(lsblk)\n"
      read -p "INFORME A PARTICAO QUE SERA ACRESCENTADA AO GRUPO DE VOLUME [ sdxx ]: " diskPart
      pvcreate /dev/$diskPart >>lvm.log
      echo -e "\n$(lvs)\n"
      read -p "INFORME O NOME DO VOLUME GORUP [ vg_NOME ]: " vg
      read -p "INFORME O NOME DO LOGICAL VOLUME [ lv_NOME ]: " lv
      vgextend $vg /dev/$diskPart >>lvm.log
      test "$?" -ne 0 && erro
      lvextend -l +100%free /dev/mapper/$vg-$lv >>lvm.log
      resize2fs /dev/mapper/$vg-$lv >>lvm.log
      sucesso
      logs >>disk$(date +%Y%m%d).log # function
   elif [ "$NUM" -eq 4 ]; then
      rescanDisk & # function
      logs >>disk$(date +%Y%m%d).log
      # funcão que chama a barra de progresso
      call_show_progress_bar

      echo -e "\n$(lsblk)\n\n"
      read -p "INFORME A PARTICAO QUE SERA REDIMENSIONADA [ sdxx ]: " disk
      echo -e "\n\n"

      partition=$(pvs | grep -i $disk | awk '{print $1}')
      growpart /dev/$(echo $partition | grep -io "[a-z]"* | tail -n1) $(echo $partition | grep -o [0-9]*) >>lvm.log

      # testa se o comando anterior apresentou erro, case "true" o script será encerrado
      test $? -eq 1 && erro && exit

      # funcao que contém os comandos de configuracao de volumes.
      redimensionar                  # function
      logs >>disk$(date +%Y%m%d).log # function
   elif [ "$NUM" -eq 5 ]; then
      echo -e "\n\033[0;31m    ***** PROGRAMA ENCRRADO PELO USUARIO *****\033[0m\n\n"
      exit
   else
      echo -e "\n\033[0;31m VALOR INSERIDO INVALIDO \033[0m \n"
      echo -e "\n\033[0;31m O PROGRAMA SERA ENCERRADO \033[0m \n"
      exit
   fi
fi
