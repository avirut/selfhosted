BACKUP_HOST=skepsis
profile_apps() {
    ROOTS=(/)
}
profile_embral() {
    ROOTS=(/home/avirut/embral "$BASE/embral/stage")
    POSTGRES='^embral-db$'
}
