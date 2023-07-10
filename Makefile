RSYNC_DIRS=	bin \
		game.graph \
		gamedata \
		gamemtl \
		particles \
		shaders_xr \
		shaders_xrlc_xr \
		stkutils
RSYNC_FILES=	ReadMe_dsh.txt

RSYNC_DEBUG=	${WITH_DEBUG:D-n}
RSYNC=	rsync -aFv ${RSYNC_DEBUG} --no-g --no-p --delete \
	"--filter=:- .gitignore"
RSYNC_FILTERS=	\
	${RSYNC_DIRS:S!^!--include=/!:S!$!/***!} \
	${RSYNC_FILES:S!^!--include=/!} \
	"--exclude=*"

fetch:
	@${RSYNC} ${RSYNC_FILTERS} ${DESTDIR}/ ./

push:
	@${RSYNC} ${RSYNC_DIRS} ${RSYNC_FILES} ${DESTDIR}/

.include "Makefile.local"
