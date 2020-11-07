TITLE Windows Application                   (WinApp.asm)
.386
.model flat,stdcall
option casemap:none
.stack 9192
; This program displays a resizable application window and
; several popup message boxes.
; Thanks to Tom Joyce for creating a prototype
; from which this program was derived.
; Last update: 9/24/01

include	 windows.inc
include	 gdi32.inc
includelib  gdi32.lib
include	 gdiplus.inc
includelib  gdiplus.lib
include	 user32.inc
includelib  user32.lib
include	 kernel32.inc
includelib  kernel32.lib
include	 winmm.inc
includelib  winmm.lib
include	 msimg32.inc
includelib  msimg32.lib
include masm32.inc
includelib  masm32.lib
include wsock32.inc
includelib  wsock32.lib

.const
Column equ 9
Row equ 17
boardsize equ 153 ;9 * (2 * 9 - 1) 
WINDOW_WIDTH equ 600
WINDOW_HEIGHT equ 900
WINDOW_TITLEBARHEIGHT equ 32

BUTTON_WIDTH equ 256
BUTTON_HEIGHT equ 70
BUTTON_X equ 172
BUTTON_Y1 equ 360
BUTTON_Y2 equ 460
BUTTON_Y3 equ 560

RETURN_WIDTH equ 80
RETURN_HEIGHT equ 75

DIALOG_X equ 100
DIALOG_Y equ 130

CELL_WIDTH equ 84
CELL_HEIGHT equ 76
ROW_CELL_SPACE equ 126
COLUMN_CELL_SPACE equ 38
CHESS_WIDTH equ 66
CHESS_HEIGHT equ 60

; HALF_CELL_WIDTH equ
ROW_CELL_SPACE_HALF equ 63
EVEN_CELL_START equ 63
;chessBg equ BMP_CHESSBG

AVATAR_WIDTH equ 96
AVATAR_HEIGHT equ AVATAR_WIDTH
SCORE_X_DELTA equ 14
SCORE_Y_DELTA equ 33

USER1_AVATAR_X equ 494
USER1_AVATAR_Y equ 794
USER1_SCORE_X equ USER1_AVATAR_X + SCORE_X_DELTA
USER1_SCORE_Y equ USER1_AVATAR_Y + SCORE_Y_DELTA

USER2_AVATAR_X equ 6
USER2_AVATAR_Y equ 6
USER2_SCORE_X equ USER2_AVATAR_X + SCORE_X_DELTA
USER2_SCORE_Y equ USER2_AVATAR_Y + SCORE_Y_DELTA

BOARD_X equ 6
BOARD_Y equ 105
CLICK_BOARD_X equ BOARD_X + CELL_WIDTH / 8
CLICK_BOARD_Y equ BOARD_Y
CLICK_CELL_WIDTH equ CELL_WIDTH / 4 * 3
CLICK_CELL_HEIGHT equ CELL_HEIGHT

INIT_SCORE equ 1000

DAMAGE_PER_CHESS equ 50

TIMER_GAMETIMER equ 1			; 游戏的默认计时器ID
TIMER_GAMETIMER_ELAPSE equ 10	; 默认计时器刷新间隔的毫秒数y

AI_DELAY_FRAME equ 20			; AI行动之前的动画延迟
CURSOR_MOVE_START_X  equ 400	;
CURSOR_MOVE_START_Y  equ 10		;

;==================== DATA =======================
.data

fontName db "script", 0
memnum128 DWORD 128
memnum2 DWORD 2
mouseX WORD 0
mouseY WORD 0

UI_STAGE BYTE 0		   ; 游戏界面场景（0为初始菜单，1为游戏场景, 2为连接输入界面, 10为胜利, 20为失败）
GAME_STATUS BYTE 0	   ; 游戏状态 (0为普通状态, 1为交换缩小，2为交换放大，3为判断, 4为消去（包含炸弹特效），5为重新生成填充)
CLICK_ENABLE BYTE 1	   ; 能否点击
REFRESH_PAINT BYTE 1   ; 是否刷新绘图

GAME_MODE BYTE 0	   ; 游戏模式（0为与AI对战，1为与网络玩家对战）
USER_TURN BYTE 0	   ; 谁的回合 (0为自己，1为对方)

USER1_SCORE DWORD 10000	   ; 我方分数
USER2_SCORE DWORD 10000	   ; 敌方分数

USER1_SCORE_TEXT db "xxxxx",0
USER1_SCORE_TEXT_LEN db 5
USER2_SCORE_TEXT db "xxxxx",0
USER2_SCORE_TEXT_LEN db 5

GOOD_SWAP BYTE 0	; 交换是否可消去

AIdelay DWORD 0		; AI交换动画延迟计数

damage DWORD 0		; 一次交换造成的伤害
DAMAGE_TEXT_PREFIX db "-"
DAMAGE_TEXT db "xxxxx", 0
DAMAGE_TEXT_LEN db 5
newScore DWORD 0		; 伤害造成后的新分数

; 棋格结构体
CELL STRUCT
    m_color    BYTE    ?    ;颜色
    m_type     BYTE    0    ;道具类型(0为普通格，1为炸弹)
    m_newColor BYTE    0    ;补充的新颜色（不为0时，表示需要消去并补充新的颜色）
	m_scale    BYTE    0    ;占位，凑4字节
CELL ENDS

; 棋盘
chessboard CELL 153 dup(<1,0,0,128>)

; 点击选择
selectedChessOne DWORD -1
selectedChessTwo DWORD -1

; 棋盘信息
cell_size DWORD 4
row_num DWORD 17
col_num DWORD 9
dir_num DWORD 6

; socket相关
local_ip DB "127.0.0.1", 0				;----------本地IP地址
server_ip DB "127.0.0.1", 128 DUP(0)	;----------服务器IP地址
port DWORD 30086					;----------端口
result DB 2048 DUP(0)					;----------接收信息结果
BUFSIZE DWORD 1024					;----------读写大小
sock DWORD ?						;----------socket
client DWORD ?						;----------客户端socket，只在等待连接模式下使用
recv_flag DWORD 0					;----------接收标识符, 0为静止，1为读取
update_flag DWORD 0					;----------更新标识符，数值对应信息头
send_flag DWORD 0					;----------发送标识符, 0为静止，其余数值对应相应的信息头
quit_flag DWORD 0					;----------终止标识符
connect_flag DWORD 0					;----------连接标识符，0表示未连接，1表示未连接

; 播放音乐命令
playSongCommand BYTE "play ./lemon.mp3", 0

; win32相关
hInstance DWORD ?
hMainWnd  DWORD ?
hDC       DWORD ?


; 定义窗口结构体
MainWin WNDCLASSEX <NULL, NULL, WinProc,NULL,NULL,NULL,NULL,NULL, \
	COLOR_WINDOW,NULL,szClassName, NULL>
msg MSG <>


szWindowName  BYTE "NanoChess",0
szClassName   BYTE "ASMWin",0


; gdip相关
m_GdiplusToken	DWORD 0;
graphics		DWORD 0;


; 文件名处理宏
$$Unicode MACRO name, string
	&name	LABEL BYTE
	FORC	char, string
		DB '&char', 0
	ENDM
		DB 0, 0
ENDM

; jpg图片文件
$$Unicode startUI, jpg\startUI.jpg			; 选中框


; png图片文件
$$Unicode startButton1, png\startButton1.png		; 人机对战按钮
$$Unicode startButton2, png\startButton2.png		; 发起对战按钮
$$Unicode startButton3, png\startButton3.png		; 连接对战按钮
$$Unicode returnButton, png\return.png				; 返回主界面
$$Unicode connectButton, png\connect.png			; 连接

$$Unicode inputDialog, png\inputIP.png		; 输入IP对话框
$$Unicode waitDialog, png\waitConnect.png	; 等待连接输入框
$$Unicode winDialog, png\win.png			; 游戏胜利
$$Unicode loseDialog, png\lose.png			; 游戏失败

$$Unicode chessBg, png\chessBg.png
$$Unicode chessRed, png\chessRed.png			; type1
$$Unicode chessPurple, png\chessPurple.png		; type2
$$Unicode chessGreen, png\chessGreen.png		; type3
$$Unicode chessOrange, png\chessOrange.png		; type4
$$Unicode chessYellow, png\chessYellow.png		; type5
$$Unicode chessBlue, png\chessBlue.png			; type6
$$Unicode chessBomb, png\chessBomb.png			; 炸弹
$$Unicode chessSelected, png\chessSelected.png			; 分数框
$$Unicode avatar, png\avatar.png
$$Unicode cursor, png\cursor.png


hFont DWORD 0

; gdip加载图片资源指针
hStartUI  DWORD 0
hStartButton1  DWORD 0
hStartButton2  DWORD 0
hStartButton3  DWORD 0
hReturnButton  DWORD 0
hConnectButton  DWORD 0
hInputDialog  DWORD 0
hWaitDialog  DWORD 0
hWinDialog  DWORD 0
hLoseDialog  DWORD 0

hChessBg  DWORD 0
hChessType1  DWORD 0
hChessType2  DWORD 0
hChessType3  DWORD 0
hChessType4  DWORD 0
hChessType5  DWORD 0
hChessType6  DWORD 0
hChessBomb  DWORD 0
hChessSelected	DWORD 0

hAvatar	DWORD 0
hCursor	DWORD 0

; proc声明
InitLoadProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
PaintProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
InitializeBoard PROTO STDCALL
LButtonDownProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
IntToString PROTO STDCALL intdata:dword, strAddrees:dword
InitGameProc PROTO STDCALL


StartupInput		GdiplusStartupInput <1, NULL, FALSE, 0>

; 记录有哪些可用颜色，不可用的标为0
possibleColor BYTE 1,2,3,4,5,6

; 记录这一轮三消中总计消掉了几个元素（打分用）
shuffleCount DWORD 0

;------------------------
.code

; -------
Str_length PROC USES edi, 
	pString:PTR BYTE
; 获取字符串的长度 
; pString是指向该字符串地址的指针 
; -----------
	mov edi,pString 
	mov eax,0 
L1: cmp BYTE PTR[edi],0  
	je L2 
	inc edi 
	inc eax 
	jmp L1 
L2: ret  
Str_length ENDP

; 获取first到second闭区间内的伪随机整数，以eax返回
GetRandomInt PROC uses ecx edx first:DWORD, second:DWORD
	invoke GetTickCount ; 取得随机数种子，也可用别的方法代替
	mov ecx, 22639      ; X = ecx = 22639
	mul ecx             ; eax = eax * X
	add eax, 38711      ; eax = eax + Y （Y = 38711）
	mov ecx, second     ; ecx = 上限
	sub ecx, first      ; ecx = 上限 - 下限
	inc ecx             ; Z = ecx + 1 （得到了范围）
	xor edx, edx        ; edx = 0
	div ecx             ; eax = eax mod Z （余数在edx里面）
	add edx, first      ; 修正产生的随机数的范围
	mov eax, edx        ; eax = Rand_Number
	ret
GetRandomInt ENDP

InitializeBoard PROC uses eax ecx edx
	; 随机初始化整个棋盘，要求不能有三连元素
	invoke GetTickCount
	invoke nseed, eax
	mov eax, 0
	.WHILE eax < 153
		; 数组里index = 0 2 4 6 8是第一行棋子 10 12 14 16是第二行棋子（数组一行9个）
		; 从而每个棋子和周围6个棋子的index的差值为-18 -10 -8 +8 +10 +18
		; 规定颜色有1,2,3,4,5,6六种
		; 如果是前两行，不需要检测
		; 编号36之前的节点（第3/4行）不需要向上方检测
		; 此外，如果是前两列（17行9列），只需要向正上方和右上方检测
		; 如果是第7/8列，需要向左上和正上方检测
		; 其余情况需要向左上、正上、右上三个方向检测
		mov [possibleColor], 1
		mov [possibleColor + 1], 2
		mov [possibleColor + 2], 3
		mov [possibleColor + 3], 4
		mov [possibleColor + 4], 5
		mov [possibleColor + 5], 6

		push eax
		mov edx, 0
		mov ecx, 9
		div ecx	; 获取当前是第几列并存在edx中
		pop eax
		.IF eax >= 18
			.IF edx == 0 || edx == 1
				push eax
				push edx
				sub eax, 8
				mov ecx, 4
				mul ecx
				add eax, OFFSET chessboard
				mov ecx, 0
				mov cl, byte ptr [eax]							; 检测右上方第一个格子
				pop edx
				pop eax

				push eax
				push edx
				push ecx
				sub eax, 16
				mov ecx, 4
				mul ecx
				pop ecx
				add eax, OFFSET chessboard
				mov ch, byte ptr [eax]							; 检测右上方第二个格子
				.IF cl == ch
					; 如果连续两个格子颜色相同，禁止选择这种颜色
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; 将这种颜色标为0，即禁止选择
				.ENDIF
				pop edx
				pop eax
				
				.IF eax >= 36								; 18,28两个格子只需要向右上检测
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]					; 检测正上方第一个格子
					pop edx
					pop eax

					push eax
					push edx
					push ecx
					sub eax, 36
					mov ecx, 4
					mul ecx
					pop ecx
					add eax, OFFSET chessboard
					mov ch, byte ptr [eax]					; 检测正上方第二个格子
					.IF cl == ch
						; 如果连续两个格子颜色相同，禁止选择这种颜色
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al						; 将这种颜色标为0，即禁止选择
					.ENDIF
					pop edx
					pop eax
				.ENDIF

			.ELSEIF edx == 7 || edx == 8
				push eax
				push edx
				sub eax, 10
				mov ecx, 4
				mul ecx
				add eax, OFFSET chessboard
				mov ecx, 0
				mov cl, byte ptr [eax]						; 检测左上方第一个格子
				pop edx
				pop eax

				push eax
				push edx
				push ecx
				sub eax, 20
				mov ecx, 4
				mul ecx
				pop ecx
				add eax, OFFSET chessboard
				mov ch, byte ptr [eax]							; 检测左上方第二个格子
				.IF cl == ch
					; 如果连续两个格子颜色相同，禁止选择这种颜色
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; 将这种颜色标为0，即禁止选择
				.ENDIF
				pop edx
				pop eax

				.IF eax >= 36								; 26,34两个格子只需要向左上检测
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]							; 检测正上方第一个格子
					pop edx
					pop eax

					push eax
					push edx
					push ecx
					sub eax, 36
					mov ecx, 4
					mul ecx
					pop ecx
					add eax, OFFSET chessboard
					mov ch, byte ptr [eax]							; 检测正上方第二个格子
					.IF cl == ch
						; 如果连续两个格子颜色相同，禁止选择这种颜色
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al							; 将这种颜色标为0，即禁止选择
					.ENDIF
					pop edx
					pop eax
				.ENDIF
			
			.ELSE
				push eax
				push edx
				sub eax, 10
				mov ecx, 4
				mul ecx
				add eax, OFFSET chessboard
				mov ecx, 0
				mov cl, byte ptr [eax]							; 检测左上方第一个格子
				pop edx
				pop eax

				push eax
				push edx
				push ecx
				sub eax, 20
				mov ecx, 4
				mul ecx
				pop ecx
				add eax, OFFSET chessboard
				mov ch, byte ptr [eax]							; 检测左上方第二个格子
				.IF cl == ch
					; 如果连续两个格子颜色相同，禁止选择这种颜色
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; 将这种颜色标为0，即禁止选择
				.ENDIF
				pop edx
				pop eax

				push eax
				push edx
				sub eax, 8
				mov ecx, 4
				mul ecx
				add eax, OFFSET chessboard
				mov ecx, 0
				mov cl, byte ptr [eax]							; 检测右上方第一个格子
				pop edx
				pop eax

				push eax
				push edx
				push ecx
				sub eax, 16
				mov ecx, 4
				mul ecx
				pop ecx
				add eax, OFFSET chessboard
				mov ch, byte ptr [eax]							; 检测右上方第二个格子
				.IF cl == ch
					; 如果连续两个格子颜色相同，禁止选择这种颜色
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; 将这种颜色标为0，即禁止选择
				.ENDIF
				pop edx
				pop eax

				.IF eax >= 36								; 26,34两个格子只需要向左上检测
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]							; 检测正上方第一个格子
					pop edx
					pop eax

					push eax
					push edx
					push ecx
					sub eax, 36
					mov ecx, 4
					mul ecx
					pop ecx
					add eax, OFFSET chessboard
					mov ch, byte ptr [eax]							; 检测正上方第二个格子
					.IF cl == ch
						; 如果连续两个格子颜色相同，禁止选择这种颜色
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al							; 将这种颜色标为0，即禁止选择
					.ENDIF
					pop edx
					pop eax
				.ENDIF
			.ENDIF
		.ENDIF

		push eax
		mov edx, eax						; 用edx存一下当前编号
		mov ecx, 0
		.WHILE ecx == 0						; 循环直到找到一种可用颜色为止
			;invoke GetRandomInt, 0, 5		; 获取一个0-5之间的随机数，存在eax(al)中
			push edx
			invoke nrandom, 6
			pop edx
			add eax, OFFSET possibleColor
			mov ecx, 0
			mov cl, byte ptr [eax]
		.ENDW
		mov eax, edx
		mov edx, 4
		mul edx
		add eax, OFFSET chessboard
		mov [eax], cl		; 完成颜色初始化
		pop eax

		add eax, 2	; 有效格子等价于下标为偶数
	.ENDW
	ret
InitializeBoard ENDP

; 传入eax对应下标的位置且此处为炸弹，位于ebx行、edx列，随机打乱周围六格（非炸弹）的颜色，并递归触发炸弹
; 且要维护shuffleCount
RandomShuffleByBomb PROC uses eax ebx ecx edx
	; 首先将炸掉的炸弹的m_type赋为100，并随机shuffle这个格子的颜色（如果未被shuffle过）
	push eax
	push ebx
	push edx
	mov ecx, 4
	mul ecx
	add eax, OFFSET chessboard
	inc eax
	mov cl, 100
	mov [eax], cl	; 对齐到m_type并置为100
	inc eax

	mov cl, byte ptr[eax]
	.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
		push eax
		inc shuffleCount
		invoke nrandom, 6
		mov edx, eax
		inc edx
		pop eax
		mov [eax], dl	; 对齐到m_newColor并随机初始化
	.ENDIF

	pop edx
	pop ebx
	pop eax

	; 从左上开始顺时针随机赋值
	.IF ebx >= 1 && edx >= 1
		; 左上
		push eax
		push ebx
		push edx
		sub eax, 10
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	.IF ebx >= 2
		; 上
		push eax
		push ebx
		push edx
		sub eax, 18
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	.IF ebx >= 1 && edx <= 7
		; 右上
		push eax
		push ebx
		push edx
		sub eax, 8
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	.IF ebx <= 15 && edx <= 7
		; 右下
		push eax
		push ebx
		push edx
		add eax, 10
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	.IF ebx <= 14
		; 下
		push eax
		push ebx
		push edx
		add eax, 18
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	.IF ebx <= 15 && edx >= 1
		; 左下
		push eax
		push ebx
		push edx
		add eax, 8
		push eax
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		inc eax
		mov cl, byte ptr[eax]
		pop eax
		.IF cl == 1
			; 如果被消掉的这个位置也是炸弹，同一轮内递归地连锁触发
			push eax
			push ebx
			push edx

			push eax
			mov edx, 0
			mov ecx, 9
			div ecx						; 获取当前是第几列并存在edx中
			pop eax

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax				; 将当前行数存在ebx中
			pop edx
			pop eax

			invoke RandomShuffleByBomb	; 连锁触发新的炸弹

			pop edx
			pop ebx
			pop eax
		.ENDIF

		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		add eax, 2		; 对齐到m_newColor
		mov cl, byte ptr[eax]
		.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
			push eax
			inc shuffleCount
			invoke nrandom, 6
			mov edx, eax
			inc edx
			pop eax
			mov [eax], dl	; 对齐到m_newColor并随机初始化
		.ENDIF

		pop edx
		pop ebx
		pop eax
	.ENDIF
	ret
RandomShuffleByBomb ENDP

; 遍历整个棋盘，查看是否存在三/四/五连的连续同颜色元素（只处理一次，不递归处理！）
; 若存在连续同颜色元素，把中间的赋为炸弹，剩下的全部随机赋值到m_newColor（为连续效果不避免重复，因而需要多次调用），且返回eax=shuffleCount，即消掉元素的准确个数
; 若整个棋盘都不存在连续同颜色元素了，返回eax=0
; 注意：调用一次就需要绘制一次新棋盘，且要重复此过程直至确保不存在连续元素为止（即返回的eax为0）
InspectAndResolveContinuousCells PROC	
	local @findContCells: DWORD
	local @currentContLength: DWORD
	local @longestContLength: DWORD
	local @longestDirection: DWORD
	local @longestIndex: DWORD
	local @currentColor: BYTE
	local @nextColor: BYTE
	; @findContCells 记录全局是否找到了3个及以上的连续元素（即棋盘是否有变动），是为1否为0
	; @currentContLength 记录当前连续相同颜色串的长度
	; @longestContLength 记录当前位置最长连续相同颜色串的长度
	; @longestDirection 记录对应当前元素最长的连续元素序列方向（0左下，1下，2右下）
	; @longestIndex 记录最长元素的位置（debug用）
	; @nextColor 只记录下一个Cell的颜色（之前的Cell颜色一定等于currentColor，否则已经跳出）
	mov @findContCells, 0
	mov @longestContLength, 1
	mov shuffleCount, 0			; 每轮开始前重置计数器
	mov eax, 0
	.WHILE eax < 153
		; 对于每一个格子，只检测左下、下、右下三个方向是否存在三个连续的相同元素
		; 越界的就不再检测了
		push eax
		mov edx, 0
		mov ecx, 9
		div ecx	; 获取当前是第几列并存在edx中
		pop eax

		push eax
		push edx
		mov ecx, 4
		mul ecx
		add eax, OFFSET chessboard
		mov al, byte ptr [eax]	; 记录当前格子的颜色
		mov @currentColor, al
		mov bl, @currentColor	; 用bl存储当前格子的颜色，方便比较
		pop edx
		pop eax
		
		; 先向左下方检测
		push eax
		push edx
		mov @currentContLength, 1
		.IF eax <= 152 - 8 && edx >= 1
			; 如果左下方第一格没有越界
			push eax
			push edx
			add eax, 8
			mov ecx, 4
			mul ecx
			add eax, OFFSET chessboard
			mov al, byte ptr [eax]	; 左下方第一个格子的颜色
			mov @nextColor, al
			pop edx
			pop eax
			.IF bl == @nextColor
				inc @currentContLength		; 连续相同颜色的长度+1
				push esi
				mov esi, @longestContLength
				.IF @currentContLength > esi
					mov esi, @currentContLength
					mov @longestContLength, esi
					mov @longestDirection, 0
					mov @longestIndex, eax
				.ENDIF
				pop esi
				.IF eax <= 152 - 16 && edx >= 2
					; 如果左下方第二格没有越界
					push eax
					push edx
					add eax, 16
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov al, byte ptr [eax]	; 左下方第二个格子的颜色
					mov @nextColor, al
					pop edx
					pop eax
					.IF bl == @nextColor
						inc @currentContLength		; 连续相同颜色的长度+1
						push esi
						mov esi, @longestContLength
						.IF @currentContLength > esi
							mov esi, @currentContLength
							mov @longestContLength, esi
							mov @longestDirection, 0
							mov @longestIndex, eax
						.ENDIF
						pop esi
						.IF eax <= 152 - 24 && edx >= 3
							; 如果左下方第三格没有越界
							push eax
							push edx
							add eax, 24
							mov ecx, 4
							mul ecx
							add eax, OFFSET chessboard
							mov al, byte ptr [eax]	; 左下方第三个格子的颜色
							mov @nextColor, al
							pop edx
							pop eax
							.IF bl == @nextColor
								inc @currentContLength		; 连续相同颜色的长度+1
								push esi
								mov esi, @longestContLength
								.IF @currentContLength > esi
									mov esi, @currentContLength
									mov @longestContLength, esi
									mov @longestDirection, 0
									mov @longestIndex, eax
								.ENDIF
								pop esi
								.IF eax <= 152 - 32 && edx >= 4
									; 如果左下方第四格没有越界
									push eax
									push edx
									add eax, 32
									mov ecx, 4
									mul ecx
									add eax, OFFSET chessboard
									mov al, byte ptr [eax]	; 左下方第四个格子的颜色
									mov @nextColor, al
									pop edx
									pop eax
									.IF bl == @nextColor
										inc @currentContLength		; 连续相同颜色的长度+1
										push esi
										mov esi, @longestContLength
										.IF @currentContLength > esi
											mov esi, @currentContLength
											mov @longestContLength, esi
											mov @longestDirection, 0
											mov @longestIndex, eax
										.ENDIF
										pop esi
									.ENDIF
								.ENDIF
							.ENDIF
						.ENDIF
					.ENDIF
				.ENDIF
			.ENDIF
		.ENDIF
		pop edx
		pop eax

		; 再向下方检测
		push eax
		push edx
		mov @currentContLength, 1
		.IF eax <= 152 - 18
			; 如果下方第一格没有越界
			push eax
			push edx
			add eax, 18
			mov ecx, 4
			mul ecx
			add eax, OFFSET chessboard
			mov al, byte ptr [eax]	; 下方第一个格子的颜色
			mov @nextColor, al
			pop edx
			pop eax
			.IF bl == @nextColor
				inc @currentContLength		; 连续相同颜色的长度+1
				push esi
				mov esi, @longestContLength
				.IF @currentContLength > esi
					mov esi, @currentContLength
					mov @longestContLength, esi
					mov @longestDirection, 1
					mov @longestIndex, eax
				.ENDIF
				pop esi
				.IF eax <= 152 - 36
					; 如果下方第二格没有越界
					push eax
					push edx
					add eax, 36
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov al, byte ptr [eax]	; 下方第二个格子的颜色
					mov @nextColor, al
					pop edx
					pop eax
					.IF bl == @nextColor
						inc @currentContLength		; 连续相同颜色的长度+1
						push esi
						mov esi, @longestContLength
						.IF @currentContLength > esi
							mov esi, @currentContLength
							mov @longestContLength, esi
							mov @longestDirection, 1
							mov @longestIndex, eax
						.ENDIF
						pop esi
						.IF eax <= 152 - 54
							; 如果下方第三格没有越界
							push eax
							push edx
							add eax, 54
							mov ecx, 4
							mul ecx
							add eax, OFFSET chessboard
							mov al, byte ptr [eax]	; 下方第三个格子的颜色
							mov @nextColor, al
							pop edx
							pop eax
							.IF bl == @nextColor
								inc @currentContLength		; 连续相同颜色的长度+1
								push esi
								mov esi, @longestContLength
								.IF @currentContLength > esi
									mov esi, @currentContLength
									mov @longestContLength, esi
									mov @longestDirection, 1
									mov @longestIndex, eax
								.ENDIF
								pop esi
								.IF eax <= 152 - 72
									; 如果下方第四格没有越界
									push eax
									push edx
									add eax, 72
									mov ecx, 4
									mul ecx
									add eax, OFFSET chessboard
									mov al, byte ptr [eax]	; 下方第四个格子的颜色
									mov @nextColor, al
									pop edx
									pop eax
									.IF bl == @nextColor
										inc @currentContLength		; 连续相同颜色的长度+1
										push esi
										mov esi, @longestContLength
										.IF @currentContLength > esi
											mov esi, @currentContLength
											mov @longestContLength, esi
											mov @longestDirection, 1
											mov @longestIndex, eax
										.ENDIF
										pop esi
									.ENDIF
								.ENDIF
							.ENDIF
						.ENDIF
					.ENDIF
				.ENDIF
			.ENDIF
		.ENDIF
		pop edx
		pop eax

		; 最后向右下方检测
		push eax
		push edx
		mov @currentContLength, 1
		.IF eax <= 152 - 10 && edx <= 7
			; 如果右下方第一格没有越界
			push eax
			push edx
			add eax, 10
			mov ecx, 4
			mul ecx
			add eax, OFFSET chessboard
			mov al, byte ptr [eax]	; 右下方第一个格子的颜色
			mov @nextColor, al
			pop edx
			pop eax
			.IF bl == @nextColor
				inc @currentContLength		; 连续相同颜色的长度+1
				push esi
				mov esi, @longestContLength
				.IF @currentContLength > esi
					mov esi, @currentContLength
					mov @longestContLength, esi
					mov @longestDirection, 2
					mov @longestIndex, eax
				.ENDIF
				pop esi
				.IF eax <= 152 - 20 && edx <= 6
					; 如果右下方第二格没有越界
					push eax
					push edx
					add eax, 20
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov al, byte ptr [eax]	; 右下方第二个格子的颜色
					mov @nextColor, al
					pop edx
					pop eax
					.IF bl == @nextColor
						inc @currentContLength		; 连续相同颜色的长度+1
						push esi
						mov esi, @longestContLength
						.IF @currentContLength > esi
							mov esi, @currentContLength
							mov @longestContLength, esi
							mov @longestDirection, 2
							mov @longestIndex, eax
						.ENDIF
						pop esi
						.IF eax <= 152 - 30 && edx <= 5
							; 如果左下方第三格没有越界
							push eax
							push edx
							add eax, 30
							mov ecx, 4
							mul ecx
							add eax, OFFSET chessboard
							mov al, byte ptr [eax]	; 右下方第三个格子的颜色
							mov @nextColor, al
							pop edx
							pop eax
							.IF bl == @nextColor
								inc @currentContLength		; 连续相同颜色的长度+1
								push esi
								mov esi, @longestContLength
								.IF @currentContLength > esi
									mov esi, @currentContLength
									mov @longestContLength, esi
									mov @longestDirection, 2
									mov @longestIndex, eax
								.ENDIF
								pop esi
								.IF eax <= 152 - 40 && edx <= 4
									; 如果右下方第四格没有越界
									push eax
									push edx
									add eax, 40
									mov ecx, 4
									mul ecx
									add eax, OFFSET chessboard
									mov al, byte ptr [eax]	; 右下方第四个格子的颜色
									mov @nextColor, al
									pop edx
									pop eax
									.IF bl == @nextColor
										inc @currentContLength		; 连续相同颜色的长度+1
										push esi
										mov esi, @longestContLength
										.IF @currentContLength > esi
											mov esi, @currentContLength
											mov @longestContLength, esi
											mov @longestDirection, 2
											mov @longestIndex, eax
										.ENDIF
										pop esi
									.ENDIF
								.ENDIF
							.ENDIF
						.ENDIF
					.ENDIF
				.ENDIF
			.ENDIF
		.ENDIF
		pop edx
		pop eax
			
		; 检测完以后，根据@longestContLength进行变化：
		; 若只有三个连续：
		;	若有炸弹，则所有炸弹周围一圈的六个格子都消掉，随机赋值颜色
		;	然后将中间元素设置为炸弹，两头随机赋值颜色
		; 若有四个连续：
		;	若有炸弹，将所有炸弹周围的六个格子都消掉，随机赋值颜色
		;	然后将中间两个元素设置为炸弹，剩下两头随机赋值颜色
		; 若有五个连续：
		;	若有炸弹，将所有炸弹周围的六个格子都消掉，随机赋值颜色
		;	然后将中间三个元素设置为炸弹，剩下两头随机赋值颜色
		.IF @longestContLength >= 3
			push eax
			push edx
			invoke GetTickCount
			invoke nseed, eax
			pop edx
			pop eax
			mov @findContCells, 1

			push eax
			push edx
			mov edx, 0
			mov ebx, 9
			div ebx
			mov ebx, eax	; 将当前行数存在ebx中
			pop edx
			pop eax

			.IF @longestDirection == 0
				; 先沿着这个方向找有没有炸弹：有炸弹则立刻将其周围六格及其本身随机赋值
				; 此时由于已知此方向有长度为@longestContLength的连续元素，不必再判断边界
				mov ecx, 0
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx

					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					mov cl, byte ptr [eax]	; 这个格子的道具类型
					pop edx
					pop ebx
					pop eax
					; 如果是炸弹，先执行周围一圈的随机初始化
					.IF cl == 1
						invoke RandomShuffleByBomb
					.ENDIF
					add eax, 8		; 向左下挪一个格子
					inc ebx
					dec edx

					pop ecx
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
					
				; 然后再执行这个方向上的随机初始化
				mov ecx, 0
				mov @currentContLength, 1	; 用来记录当前走到第几格了，从而确定炸弹安放位置
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx
					
					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					push eax
					.IF @longestContLength == 3 && @currentContLength == 2
						mov dl, 1
						mov [eax], dl
						dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
						mov dl, [eax]
						add eax, 2		; 将m_newColor赋为m_color
						mov [eax], dl
					.ELSEIF @longestContLength == 4
						.IF @currentContLength == 2 || @currentContLength == 3
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ELSEIF @longestContLength == 5
						.IF @currentContLength == 2 || @currentContLength == 3 || @currentContLength == 4
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ENDIF
					pop eax
					inc eax		; 再对齐到m_newColor
					
					mov cl, byte ptr [eax]
					.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
						push eax
						inc shuffleCount
						invoke nrandom, 6
						mov edx, eax
						inc edx
						pop eax
						mov [eax], dl	; 对齐到m_newColor并随机初始化
					.ENDIF
					
					pop edx
					pop ebx
					pop eax

					add eax, 8		; 向左下挪一个格子
					inc ebx
					dec edx

					pop ecx
					inc @currentContLength
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
			.ELSEIF @longestDirection == 1
				; 先沿着这个方向找有没有炸弹：有炸弹则立刻将其周围六格及其本身随机赋值
				; 此时由于已知此方向有长度为@longestContLength的连续元素，不必再判断边界
				mov ecx, 0
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx

					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					mov cl, byte ptr [eax]	; 这个格子的道具类型
					pop edx
					pop ebx
					pop eax
					; 如果是炸弹，先执行周围一圈的随机初始化
					.IF cl == 1
						invoke RandomShuffleByBomb
					.ENDIF
					add eax, 18		; 向下挪一个格子
					add ebx, 2

					pop ecx
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
					
				; 然后再执行这个方向上的随机初始化
				mov ecx, 0
				mov @currentContLength, 1	; 用来记录当前走到第几格了，从而确定炸弹安放位置
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx
					
					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					push eax
					.IF @longestContLength == 3 && @currentContLength == 2
						mov dl, 1
						mov [eax], dl
						dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
						mov dl, [eax]
						add eax, 2		; 将m_newColor赋为m_color
						mov [eax], dl
					.ELSEIF @longestContLength == 4
						.IF @currentContLength == 2 || @currentContLength == 3
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ELSEIF @longestContLength == 5
						.IF @currentContLength == 2 || @currentContLength == 3 || @currentContLength == 4
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ENDIF
					pop eax
					inc eax		; 再对齐到m_newColor

					mov cl, byte ptr[eax]
					.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
						push eax
						inc shuffleCount
						invoke nrandom, 6
						mov edx, eax
						inc edx
						pop eax
						mov [eax], dl	; 对齐到m_newColor并随机初始化
					.ENDIF

					pop edx
					pop ebx
					pop eax

					add eax, 18		; 向下挪一个格子
					add ebx, 2

					pop ecx
					inc @currentContLength
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
			.ELSEIF @longestDirection == 2
				; 先沿着这个方向找有没有炸弹：有炸弹则立刻将其周围六格及其本身随机赋值
				; 此时由于已知此方向有长度为@longestContLength的连续元素，不必再判断边界
				mov ecx, 0
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx

					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					mov cl, byte ptr [eax]	; 这个格子的道具类型
					pop edx
					pop ebx
					pop eax
					; 如果是炸弹，先执行周围一圈的随机初始化
					.IF cl == 1
						invoke RandomShuffleByBomb
					.ENDIF
					add eax, 10		; 向右下挪一个格子
					inc ebx
					inc edx

					pop ecx
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
					
				; 然后再执行这个方向上的随机初始化
				mov ecx, 0
				mov @currentContLength, 1	; 用来记录当前走到第几格了，从而确定炸弹安放位置
				push eax
				push ebx
				push edx
				.WHILE ecx < @longestContLength
					push ecx
					
					push eax
					push ebx
					push edx
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					inc eax		; 对齐到m_type
					push eax
					.IF @longestContLength == 3 && @currentContLength == 2
						mov dl, 1
						mov [eax], dl
						dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
						mov dl, [eax]
						add eax, 2		; 将m_newColor赋为m_color
						mov [eax], dl
					.ELSEIF @longestContLength == 4
						.IF @currentContLength == 2 || @currentContLength == 3
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ELSEIF @longestContLength == 5
						.IF @currentContLength == 2 || @currentContLength == 3 || @currentContLength == 4
							mov dl, 1
							mov [eax], dl
							dec eax			; 记录原来的m_color（生成炸弹格子的颜色不变）
							mov dl, [eax]
							add eax, 2		; 将m_newColor赋为m_color
							mov [eax], dl
						.ENDIF
					.ENDIF
					pop eax
					inc eax		; 再对齐到m_newColor
					
					mov cl, byte ptr[eax]
					.IF cl == 0		; 如果这个格子在这一轮内还没有被shuffle过(m_newColor=0)
						push eax
						inc shuffleCount
						invoke nrandom, 6
						mov edx, eax
						inc edx
						pop eax
						mov [eax], dl	; 对齐到m_newColor并随机初始化
					.ENDIF
					
					pop edx
					pop ebx
					pop eax

					add eax, 10		; 向右下挪一个格子
					inc ebx
					inc edx

					pop ecx
					inc @currentContLength
					inc ecx
				.ENDW
				pop edx
				pop ebx
				pop eax
			.ENDIF
			jmp foundAndExit	; 每一轮只需要处理一个三消
		.ENDIF

		add eax, 2	; 有效格子等价于下标为偶数
	.ENDW
foundAndExit:
	mov eax, shuffleCount	; 返回这一轮shuffle的元素的个数
	ret
InspectAndResolveContinuousCells ENDP

; 解析收到的信息
; 信息头有3种类型，1代表交换的棋子，2代表棋盘信息和分数，3代表终止符
parse_recv PROC uses esi eax ebp
	LOCAL flag: DWORD
	LOCAL count: DWORD

	; 获取信息头
	mov esi, OFFSET result
	mov eax, DWORD PTR [esi]
	mov flag, eax
	add esi, 4

	.if flag == 1					; 交换棋子
		mov update_flag, 1

		mov eax, DWORD PTR [esi]
		mov selectedChessOne, eax
		add esi, 4
		mov eax, DWORD PTR [esi]
		mov selectedChessTwo, eax
		add esi, 4
		mov eax, DWORD PTR [esi]
		mov damage, eax
		add esi, 4

		mov ebp, OFFSET chessboard
		mov count, 0
		.while count < 153			
			mov eax, DWORD PTR [esi]
			mov DWORD PTR [ebp], eax
			
			add ebp, 4
			add esi, 4
			inc count
		.endw
	.elseif flag == 2				; 棋盘信息
		mov update_flag, 2

		mov eax, DWORD PTR [esi]
		mov damage, eax
		add esi, 4

		mov ebp, OFFSET chessboard
		mov count, 0
		.while count < 153			
			mov eax, DWORD PTR [esi]
			mov DWORD PTR [ebp], eax
			
			add ebp, 4
			add esi, 4
			inc count
		.endw
	.elseif flag == 3				; 终止符
		mov update_flag, 3
		
	.endif

	mov recv_flag, 0
	ret
parse_recv ENDP

; 设置发送的信息
; 信息头定义见上文
set_send PROC uses esi eax ebp
	LOCAL count: DWORD

	; 初始化result
	; 设置信息头
	mov esi, OFFSET result
	mov eax, send_flag
	mov DWORD PTR [esi], eax
	add esi, 4

	.if send_flag == 1				; 发送交换棋子
		mov eax, selectedChessOne
		mov DWORD PTR [esi], eax
		add esi, 4
		mov eax, selectedChessTwo
		mov DWORD PTR [esi], eax
		add esi, 4
		mov eax, damage
		mov DWORD PTR [esi], eax
		add esi, 4
		
		mov ebp, OFFSET chessboard
		mov count, 0
		.while count < 153
			mov eax, DWORD PTR [ebp]
			mov DWORD PTR [esi], eax
			add ebp, 4
			add esi, 4
			inc count
		.endw
	.elseif send_flag == 2			; 发送棋盘信息
		mov eax, damage
		mov DWORD PTR [esi], eax
		add esi, 4
		
		mov ebp, OFFSET chessboard
		mov count, 0
		.while count < 153
			mov eax, DWORD PTR [ebp]
			mov DWORD PTR [esi], eax
			add ebp, 4
			add esi, 4
			inc count
		.endw
	.elseif send_flag == 3			; 发送终止符
		mov recv_flag, 1
	.endif

	; 所有信息只发送一次，所以发完后就把flag置为静止
	mov send_flag, 0
	ret
set_send ENDP

server_socket PROC uses esi edi
	LOCAL sock_data: WSADATA
	LOCAL s_addr: sockaddr_in
	LOCAL c_addr: sockaddr_in
	LOCAL len: DWORD
	LOCAL is_read: DWORD

	mov len, SIZEOF s_addr

	; 初始化
	mov recv_flag, 0					
	mov update_flag, 0					
	mov send_flag, 0				
	mov quit_flag, 0						
	mov connect_flag, 0

	INVOKE WSAStartup, 22h, ADDR sock_data
	.IF eax != 0
		ret
	.ENDIF

	; 设置服务器ip和端口
	lea esi, s_addr
	mov WORD PTR [esi], AF_INET
	INVOKE htons, port
	mov WORD PTR [esi + 2], ax
	INVOKE inet_addr, ADDR local_ip
	mov DWORD PTR [esi + 4], eax

	; 创建并连接socket
	INVOKE socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
	mov sock, eax
	lea esi, s_addr
	INVOKE bind, sock, ADDR s_addr, SIZEOF s_addr
	INVOKE listen, sock, 10
	INVOKE accept, sock, ADDR c_addr, ADDR len
	mov client, eax
	mov connect_flag, 1

	; 根据读取标识符在读取状态之间不断地切换
	.while 1
		.if recv_flag != 0
			INVOKE recv, client, ADDR  result, BUFSIZE, 0		
			INVOKE parse_recv
			.continue
		.endif

		.if send_flag != 0
			INVOKE set_send
			INVOKE send, client, ADDR result, BUFSIZE, 0
			.continue
		.endif
		
		; 退出
		.if quit_flag == 1
			.break
		.endif
	.endw

	; 清理
	INVOKE closesocket, sock
	INVOKE WSACleanup
	ret
server_socket ENDP

client_socket PROC uses esi edi
	LOCAL sock_data: WSADATA
	LOCAL s_addr: sockaddr_in

	; 初始化
	mov recv_flag, 0					
	mov update_flag, 0					
	mov send_flag, 0				
	mov quit_flag, 0						
	mov connect_flag, 0
	INVOKE WSAStartup, 22h, ADDR sock_data
	.IF eax != 0
		ret
	.ENDIF

	; 设置服务器ip和端口
	lea esi, s_addr
	mov WORD PTR [esi], AF_INET
	INVOKE htons, port
	mov WORD PTR [esi + 2], ax
	INVOKE inet_addr, ADDR server_ip
	mov DWORD PTR [esi + 4], eax

	; 创建并连接socket
	INVOKE socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
	mov sock, eax
	lea esi, s_addr
	INVOKE connect, sock, esi, SIZEOF sockaddr_in
	mov connect_flag, 1

	; 根据读取标识符在读取状态之间不断地切换
	.while 1
		.if recv_flag != 0
			INVOKE recv, sock, ADDR  result, BUFSIZE, 0
			INVOKE parse_recv
			.continue
		.endif

		.if send_flag != 0
			INVOKE set_send
			INVOKE send, sock, ADDR result, BUFSIZE, 0
			.continue
		.endif
		
		; 退出
		.if quit_flag == 1
			.break
		.endif
	.endw
	
	; 清理
	INVOKE closesocket, sock
	INVOKE WSACleanup
	ret
client_socket ENDP

;------------------获取目标地址
Cal_address PROC src: DWORD,
				 row: DWORD,
				 col: DWORD
	push edx
	push ecx
	mov eax, row
	mul col_num
	mul cell_size
	add src, eax
	mov eax, col
	mul cell_size
	add src, eax
	mov eax, src
	pop ecx
	pop edx
	ret
Cal_address ENDP

;------------------交换函数
;------------------依照顺序交换左上、上、右上、左下、下、右下
All_Swap PROC dir: DWORD,
			  row: DWORD,
			  col: DWORD
			  local @target_row: DWORD
			  local @target_col: DWORD
			  local @chess_1: CELL
			  local @chess_2: CELL
	pushad
	mov eax, row
	mov @target_row, eax
	mov eax, col
	mov @target_col, eax
	mov ecx, dir
	.if ecx == 0
		dec @target_row
		dec @target_col
	.elseif ecx == 1
		sub @target_row, 2
	.elseif ecx == 2
		dec @target_row
		inc @target_col
	.elseif ecx == 3
		inc @target_row
		dec @target_col
	.elseif ecx == 4
		add @target_row, 2
	.elseif ecx == 5
		inc @target_row
		inc @target_col
	.endif

	mov ebx, @target_row
	mov ecx, @target_col
	.if ebx < 0 || ebx >= row_num || ecx < 0 || ecx >= col_num
		mov eax, 0
		ret
	.endif

	INVOKE Cal_address, OFFSET chessboard, row, col
	mov edx, eax
	mov eax, [edx]
	mov @chess_1, eax

	INVOKE Cal_address, OFFSET chessboard, @target_row, @target_col
	mov ebx, [eax]
	mov @chess_2, ebx
	
	mov ebx, @chess_1
	mov [eax], ebx
	mov ebx, @chess_2
	mov [edx], ebx

	popad
	ret
All_Swap ENDP

;------------------计数有多少个相同色的棋子连在一起
Count PROC row: DWORD,
		   col: DWORD,
		   color: BYTE,
		   dir: DWORD
		   local @chess: CELL
		   local @target_row: DWORD
		   local @target_col: DWORD
		   local @count: DWORD
		   local @bonus_count:DWORD
		   local @flag:DWORD

	push ecx
	push ebx
	push edx

	mov edx, OFFSET chessboard
	mov eax, row
	mov @target_row, eax
	mov eax, col
	mov @target_col, eax
	mov @count, 1
	mov @bonus_count, 0
	INVOKE Cal_address, edx, @target_row, @target_col
	mov eax, [eax]
	mov @chess, eax
	.if @chess.m_type == 1
		inc @bonus_count
	.endif
	
	mov @flag, 1

	.while @flag == 1
		.if	dir == 0		
			dec @target_row
			dec @target_col
		.elseif dir == 1
			sub @target_row, 2
		.elseif dir == 2
			dec @target_row
			inc @target_col
		.endif

		mov eax, @target_row
		mov ebx, @target_col
		.if eax >= 0 && eax < row_num && ebx >= 0 && ebx < col_num
			INVOKE Cal_address, edx, @target_row, @target_col
			mov eax, [eax]
			mov @chess, eax
			mov al, @chess.m_color
			.if al == color
				inc @count
				.if @chess.m_type == 1
					inc @bonus_count
				.endif
			.else
				mov @flag, 0
			.endif
		.else
			mov @flag, 0
		.endif
	.endw

	mov eax, row
	mov @target_row, eax
	mov eax, col
	mov @target_col, eax
	mov @flag, 1
	.while @flag == 1
		.if	dir == 0		
			inc @target_row
			inc @target_col
		.elseif dir == 1
			add @target_row, 2
		.elseif dir == 2
			inc @target_row
			dec @target_col
		.endif
			
		mov eax, @target_row
		mov ebx, @target_col
		.if eax >= 0 && eax < row_num && ebx >= 0 && ebx < col_num		
			INVOKE Cal_address, edx, @target_row, @target_col
			mov eax, [eax]
			mov @chess, eax
			mov al, @chess.m_color
			.if al == color
				inc @count
				.if @chess.m_type == 1
					inc @bonus_count
				.endif
			.else
				mov @flag, 0
			.endif
		.else
			mov @flag, 0
		.endif
	.endw

	mov eax, 0
	.if @count >= 3
		mov eax, 10
		mul @count
		.if @bonus_count > 0
			add eax, 300
		.endif
	.endif

	
	pop edx
	pop ebx
	pop ecx
	ret
Count ENDP

;------------------从单个棋子出发，给出评分
Grade PROC	row: DWORD,
			col: DWORD
			local @chess: CELL
			local @color: BYTE
			local @dir: DWORD
			local @score: DWORD
	push edx
	mov edx, OFFSET chessboard
	INVOKE Cal_address, edx, row, col
	mov eax, [eax]
	mov @chess, eax
	mov al, @chess.m_color
	mov @color, al 
	mov @dir, 0
	mov @score, 0

	.WHILE @dir < 3
		INVOKE Count, row, col, @color, @dir
		add @score, eax
		inc @dir
	.endw

	mov eax, @score
	pop edx
	ret
Grade ENDP

;------------------AI
;------------------采用贪心的方式，当前所有的可能选择得分最高的一种
AI PROC
		local @chess_1: CELL						;要移动的棋子一
		local @chess_2: CELL						;要移动的棋子二
		local @row: DWORD							;当前遍历的行
		local @col: DWORD							;当前遍历的列
		local @dir: DWORD							;当前遍历的方向
		local @target_row: DWORD					;目标行
		local @target_col: DWORD					;目标列
		local @max_score: DWORD						;最大得分
		local @score: DWORD							;当前得分
		local @type: DWORD							;每行有5个或4个棋子，分为5、4两个类

	pushad
	mov @max_score, 0			
	mov @row, 0
	mov @col, 0
	mov @dir, 0
	mov @target_row, 0
	mov @target_col, 0
	mov edx, OFFSET chessboard
	mov @type, 5

	mov ecx, 0
	.WHILE ecx < row_num
		push ecx

		.if @type == 5
			mov ecx, 0
		.elseif	@type == 4
			mov ecx, 1
		.endif
		mov @col, ecx

		.WHILE ecx < col_num
			push ecx
			mov ecx, 0
			mov @dir, ecx

			.WHILE ecx < dir_num
				push ecx

				INVOKE All_Swap, @dir, @row, @col
				mov eax, @row
				mov @target_row, eax
				mov eax, @col
				mov @target_col, eax
				.if @dir == 0
					dec @target_row
					dec @target_col
				.elseif @dir == 1
					sub @target_row, 2
				.elseif @dir == 2
					dec @target_row
					inc @target_col
				.elseif @dir == 3
					inc @target_row
					dec @target_col
				.elseif @dir == 4
					add @target_row, 2
				.elseif @dir == 5
					inc @target_row
					inc @target_col
				.endif

				.if eax > 0
					INVOKE Grade, @row, @col
					mov @score, eax
					INVOKE Grade, @target_row, @target_col
					add @score, eax
					mov ebx, @score
					.if ebx > @max_score
						mov selectedChessOne, 0
						mov eax, @row
						mul col_num
						add selectedChessOne, eax
						mov eax, @col
						add selectedChessOne, eax
						
						mov selectedChessTwo, 0
						mov eax, @target_row
						mul col_num
						add selectedChessTwo, eax
						mov eax, @target_col
						add selectedChessTwo, eax
						
						mov eax, @score
						mov @max_score, eax
					.endif
				.endif
				INVOKE All_Swap, @dir, @row, @col
				
				pop ecx
				inc ecx
				inc @dir
			.endw

			pop ecx
			add ecx, 2
			add @col ,2
		.endw

		;每行之间类型发生变换
		.if @type == 5
			mov @type, 4
		.elseif	@type == 4
			mov @type, 5
		.endif
		pop ecx
		inc ecx
		inc @row
	.endw

	popad
	ret
AI ENDP

;-----------
IntToString PROC uses eax ebx edx edi intdata:dword, strAddrees:dword
; 5位数的整数(DWORD)转换成5字符字符串(DWORD)
;--------------
	mov eax, intdata
	mov edi, strAddrees
	add edi, 4
	.while edi >= strAddrees
		mov ebx, 10
		mov edx, 0
		div ebx
		add edx, 48
		mov [edi], dl
		sub edi, 1
	.endw
	ret
IntToString ENDP

;-----------------------
WinMain PROC
; windows窗口程序入口函数
;--------------
	; 播放音乐
	; invoke mciSendString, ADDR playSongCommand, NULL, 0, NULL;


	; 获得当前程序句柄
	INVOKE GetModuleHandle, NULL
	mov hInstance, eax
	mov MainWin.hInstance, eax

	mov MainWin.cbSize, sizeof WNDCLASSEX
	mov MainWin.style, CS_HREDRAW or CS_VREDRAW

	; 获取图标和光标
	INVOKE LoadIcon, NULL, IDI_APPLICATION
	mov MainWin.hIcon, eax
	INVOKE LoadCursor, NULL, IDC_ARROW
	mov MainWin.hCursor, eax

	;mov MainWin.cbSize, sizeof WNDCLASSEX
	;mov MainWin.style, CS_HREDRAW or CS_VREDRAW
	mov MainWin.hbrBackground, COLOR_MENUTEXT + 1

	; 注册窗口
	INVOKE RegisterClassEx, ADDR MainWin
	.IF eax == 0
	  ;call ErrorHandler
	  jmp Exit_Program
	.ENDIF

	; 初始化GDI+
	INVOKE	GdiplusStartup, ADDR m_GdiplusToken, ADDR StartupInput, 0

	; Create the application's main window.
	; Returns a handle to the main window in EAX.
	INVOKE CreateWindowEx, 0, ADDR szClassName,
	  ADDR szWindowName, WS_CAPTION or WS_SYSMENU,
	  CW_USEDEFAULT, CW_USEDEFAULT, WINDOW_WIDTH + 16,
	  WINDOW_HEIGHT + WINDOW_TITLEBARHEIGHT, NULL, NULL, hInstance, NULL
	mov hMainWnd, eax

	; If CreateWindowEx failed, display a message & exit.
	.IF eax == 0
	  call ErrorHandler
	  jmp  Exit_Program
	.ENDIF

	;INVOKE  GetDC, hMainWnd      
    ;;mov	hDC, eax
	;INVOKE GdipCreateFromHWND, hMainWnd, OFFSET graphics
	;INVOKE GdipCreateFromHDC, hDC, OFFSET graphics

	; Show and draw the window.
	INVOKE ShowWindow, hMainWnd, SW_SHOW
	INVOKE UpdateWindow, hMainWnd


	; Begin the program's message-handling loop.
Message_Loop:
	; Get next message from the queue.
	INVOKE GetMessage, ADDR msg, NULL,NULL,NULL

	; Quit if no more messages.
	.IF eax == 0
	  jmp Exit_Program
	.ENDIF

	; Relay the message to the program's WinProc.
	INVOKE TranslateMessage, ADDR msg
	INVOKE DispatchMessage, ADDR msg
    jmp Message_Loop

Exit_Program:
	INVOKE ExitProcess,0
	ret
WinMain ENDP

;-------------------
TimerUpdate PROC,
	hWnd:DWORD
; 更新数据（m_color, m_scale最好只在其中更新）
;----------------
	local	@i:DWORD
	local	@j:DWORD
	local	@cell1:CELL
	local	@cell2:CELL
	local	@chessAddress1:DWORD
	local	@chessAddress2:DWORD

	.IF UI_STAGE == 0
		; 游戏初始菜单

	.ELSEIF UI_STAGE == 1
		; 游戏场景

		.IF GAME_STATUS == 1
			; 交换缩小
			mov eax, selectedChessOne
			mov ebx, TYPE CELL
			mul ebx
			add eax, OFFSET chessboard
			mov @chessAddress1, eax
			mov eax, [eax]
			mov @cell1, eax

			mov eax, selectedChessTwo
			mov ebx, TYPE CELL
			mul ebx
			add eax, OFFSET chessboard
			mov @chessAddress2, eax
			mov eax, [eax]
			mov @cell2, eax

			.IF @cell1.m_scale == 1
				;mov al, @cell1.m_color
				;mov ah, @cell2.m_color
				;mov @cell1.m_color, ah
				;mov @cell2.m_color, al
				mov ebx, @chessAddress2
				mov eax, @cell1
				mov [ebx], eax
				mov ebx, @chessAddress1
				mov eax, @cell2
				mov [ebx], eax
				
				mov GAME_STATUS, 2
			.ELSE
				movzx eax, @cell1.m_scale
				mov edx, 0
				div memnum2
				mov @cell1.m_scale, al
				movzx eax, @cell2.m_scale
				mov edx, 0
				div memnum2
				mov @cell2.m_scale, al
				mov ebx, @chessAddress1
				mov eax, @cell1
				mov [ebx], eax
				mov ebx, @chessAddress2
				mov eax, @cell2
				mov [ebx], eax
			.ENDIF
		.ELSEIF GAME_STATUS == 2
			; 交换放大
			mov eax, selectedChessOne
			mov ebx, TYPE CELL
			mul ebx
			add eax, OFFSET chessboard
			mov @chessAddress1, eax
			mov eax, [eax]
			mov @cell1, eax

			mov eax, selectedChessTwo
			mov ebx, TYPE CELL
			mul ebx
			add eax, OFFSET chessboard
			mov @chessAddress2, eax
			mov eax, [eax]
			mov @cell2, eax

			.IF @cell1.m_scale == 0
				mov @cell1.m_scale, 1
				mov @cell2.m_scale, 1
				mov ebx, @chessAddress1
				mov eax, @cell1
				mov [ebx], eax
				mov ebx, @chessAddress2
				mov eax, @cell2
				mov [ebx], eax
				
				mov GAME_STATUS, 2
			.ELSEIF @cell1.m_scale != 128
				movzx eax, @cell1.m_scale
				mul memnum2
				mov @cell1.m_scale, al
				movzx eax, @cell2.m_scale
				mul memnum2
				mov @cell2.m_scale, al
				mov ebx, @chessAddress1
				mov eax, @cell1
				mov [ebx], eax
				mov ebx, @chessAddress2
				mov eax, @cell2
				mov [ebx], eax
			.ELSE
				.IF GOOD_SWAP == 1
					; 前往判断是否存在三消
					mov GAME_STATUS, 3
				.ELSE
					; 判断不存在三消将两个棋子又交换回去后，回到游戏场景（可以再次选择交换）
					mov selectedChessOne, -1
					mov GAME_STATUS, 0
					mov CLICK_ENABLE, 1
				.ENDIF
			.ENDIF

		.ELSEIF GAME_STATUS == 3
			.IF USER_TURN == 0 && USER2_SCORE == 0
				mov UI_STAGE, 10
				mov CLICK_ENABLE, 1
			.ELSEIF USER_TURN == 1 && USER1_SCORE == 0
				mov UI_STAGE, 20
				mov CLICK_ENABLE, 1
			.ELSE
				.IF GAME_MODE == 0
					; 判断是否存在三消
					INVOKE InspectAndResolveContinuousCells
					.IF eax == 0
						; 不存在三消
						.IF GOOD_SWAP == 1
							; 之前也没有触发三消，则将两棋子交换回去
							mov GOOD_SWAP, 0
							mov GAME_STATUS, 1
						.ELSE
							; 之前触发了三消，则直接回到游戏场景
							mov selectedChessOne, -1
							.IF GAME_MODE == 0
								.IF USER_TURN == 0
									INVOKE AI
									mov GOOD_SWAP, 1
									mov GAME_STATUS, 6
									mov USER_TURN, 1
								.ELSEIF USER_TURN == 1
									mov GAME_STATUS, 0
									mov CLICK_ENABLE, 1
									mov USER_TURN, 0
								.ENDIF
							.ELSEIF GAME_MODE == 1
								
							.ENDIF
						.ENDIF
					.ELSE
						; 存在三消，消去棋子并显示新棋子
						mov ebx, DAMAGE_PER_CHESS
						mul ebx
						mov damage, eax
						.IF USER_TURN == 0
							mov eax, USER2_SCORE
							sub eax, damage
							mov newScore, eax
						.ELSEIF USER_TURN == 1
							mov eax, USER1_SCORE
							sub eax, damage
							mov newScore, eax
						.ENDIF
						.IF newScore < 0 || newScore > INIT_SCORE
							mov newScore, 0
						.ENDIF
						INVOKE IntToString, damage, ADDR DAMAGE_TEXT
						mov GOOD_SWAP, 0
						mov GAME_STATUS, 4
					.ENDIF
				.ELSEIF GAME_MODE == 1
					.IF USER_TURN == 0
						; 判断是否存在三消
						INVOKE InspectAndResolveContinuousCells
						.IF eax == 0
							; 不存在三消
							.IF GOOD_SWAP == 1
								; 之前也没有触发三消，则将两棋子交换回去
								mov GOOD_SWAP, 0
								mov GAME_STATUS, 1
							.ELSE
								; 之前触发了三消，则告诉对方没有三消了，轮到对方下棋
								mov selectedChessOne, -1
								mov send_flag, 3
								mov GOOD_SWAP, 1
								mov GAME_STATUS, 7
								mov USER_TURN, 1
							.ENDIF
						.ELSE
							; 存在三消，消去棋子并显示新棋子
							mov ebx, DAMAGE_PER_CHESS
							mul ebx
							mov damage, eax
							.IF GOOD_SWAP == 1
								mov send_flag, 1
							.ELSEIF GOOD_SWAP == 0
								mov send_flag, 2
							.ENDIF
							.IF USER_TURN == 0
								mov eax, USER2_SCORE
								sub eax, damage
								mov newScore, eax
							.ELSEIF USER_TURN == 1
								mov eax, USER1_SCORE
								sub eax, damage
								mov newScore, eax
							.ENDIF
							.IF newScore < 0 || newScore > INIT_SCORE
								mov newScore, 0
							.ENDIF
							INVOKE IntToString, damage, ADDR DAMAGE_TEXT
							mov GOOD_SWAP, 0
							mov GAME_STATUS, 4
						.ENDIF
					.ELSEIF USER_TURN == 1
						.IF GOOD_SWAP == 1
							mov eax, USER1_SCORE
							sub eax, damage
							mov newScore, eax
							.IF newScore < 0 || newScore > INIT_SCORE
								mov newScore, 0
							.ENDIF
							INVOKE IntToString, damage, ADDR DAMAGE_TEXT
							mov GOOD_SWAP, 0
							mov GAME_STATUS, 4
						.ELSEIF
							.IF update_flag == 2
								mov update_flag, 0
								mov eax, USER1_SCORE
								sub eax, damage
								mov newScore, eax
								.IF newScore < 0 || newScore > INIT_SCORE
									mov newScore, 0
								.ENDIF
								INVOKE IntToString, damage, ADDR DAMAGE_TEXT
								mov GOOD_SWAP, 0
								mov GAME_STATUS, 4
							.ELSEIF update_flag == 3
								mov update_flag, 0
								mov selectedChessOne, -1
								mov USER_TURN, 0
								mov GAME_STATUS, 0
								mov CLICK_ENABLE, 1
							.ENDIF
						.ENDIF
					.ENDIF
				.ENDIF
			.ENDIF
		.ELSEIF GAME_STATUS == 4
			; 消去的棋子缩小到消去
			mov @i, 0
			mov eax, OFFSET chessboard
			mov @chessAddress1, eax

			.WHILE @i < boardsize
				mov eax, @chessAddress1
				mov eax, [eax]
				mov @cell1, eax

				.IF @cell1.m_newColor != 0
					.IF @cell1.m_scale == 1
						mov al, @cell1.m_newColor
						mov @cell1.m_color, al
						.IF @cell1.m_type == 100
							mov @cell1.m_type, 0
						.ENDIF
						mov ebx, @chessAddress1
						mov eax, @cell1
						mov [ebx], eax
						mov GAME_STATUS, 5
					.ELSE
						movzx eax, @cell1.m_scale
						mov edx, 0
						div memnum2
						mov @cell1.m_scale, al
						mov ebx, @chessAddress1
						mov eax, @cell1
						mov [ebx], eax
					.ENDIF
				.ENDIF
				add @i, 2
				mov eax, 2 * TYPE CELL
				add @chessAddress1, eax
			.ENDW

			.IF GAME_STATUS == 4
				mov eax, damage
				mov edx, 0
				mov ebx, 6
				div ebx
				.IF USER_TURN == 0
					sub USER2_SCORE, eax
					.IF USER2_SCORE < 0 || USER2_SCORE > INIT_SCORE
						mov USER2_SCORE, 0
					.ENDIF
					INVOKE IntToString, USER2_SCORE, ADDR USER2_SCORE_TEXT
				.ELSEIF USER_TURN == 1
					sub USER1_SCORE, eax
					.IF USER1_SCORE < 0 || USER1_SCORE > INIT_SCORE
						mov USER1_SCORE, 0
					.ENDIF
					INVOKE IntToString, USER1_SCORE, ADDR USER1_SCORE_TEXT
				.ENDIF
			.ELSEIF GAME_STATUS == 5
				mov eax, newScore
				.IF USER_TURN == 0
					mov USER2_SCORE, eax
					INVOKE IntToString, USER2_SCORE, ADDR USER2_SCORE_TEXT
				.ELSEIF USER_TURN == 1
					mov USER1_SCORE, eax
					INVOKE IntToString, USER1_SCORE, ADDR USER1_SCORE_TEXT
				.ENDIF
				mov newScore, 0
				mov damage, 0
				INVOKE IntToString, damage, ADDR DAMAGE_TEXT
			.ENDIF

		.ELSEIF GAME_STATUS == 5
			; 生成的新棋子放大填充
			mov @i, 0
			mov eax, OFFSET chessboard
			mov @chessAddress1, eax

			.WHILE @i < boardsize
				mov eax, @chessAddress1
				mov eax, [eax]
				mov @cell1, eax

				.IF @cell1.m_newColor != 0
					.IF @cell1.m_scale != 128
						movzx eax, @cell1.m_scale
						mul memnum2
						mov @cell1.m_scale, al
						mov ebx, @chessAddress1
						mov eax, @cell1
						mov [ebx], eax
					.ELSE
						mov @cell1.m_newColor, 0
						mov ebx, @chessAddress1
						mov eax, @cell1
						mov [ebx], eax
						mov GAME_STATUS, 3
					.ENDIF
				.ENDIF
				add @i, 2
				mov eax, 2 * TYPE CELL
				add @chessAddress1, eax
			.ENDW
		.ELSEIF GAME_STATUS == 6
			; 对手交换棋子动画过程
			add AIdelay, 1
			.IF AIdelay == AI_DELAY_FRAME
				mov AIdelay, 0
				mov GAME_STATUS, 1
			.ENDIF
		.ELSEIF GAME_STATUS == 7
			; 远程对战模式下等待对方交换棋子
			.IF update_flag == 1
				mov update_flag, 0
				mov GAME_STATUS, 6
			.ENDIF
		.ENDIF

	.ELSEIF UI_STAGE == 2
		; 等待远程玩家连接
		.IF connect_flag == 1
			INVOKE InitGameProc
			mov updateflag, 2
			mov send_flag, 1
			mov connect_flag, 0
		.ENDIF
	.ELSEIF UI_STAGE == 3
		; 准备连接远程玩家
		.IF connect_flag == 1
			mov recv_flag, 1
			mov connect_flag, 0
		.ELSEIF update_flag == 2
			mov update_flag, 0
			mov USER1_SCORE, INIT_SCORE
			INVOKE IntToString, USER1_SCORE, ADDR USER1_SCORE_TEXT
			mov USER2_SCORE, INIT_SCORE
			INVOKE IntToString, USER2_SCORE, ADDR USER2_SCORE_TEXT
			mov selectedChessOne, -1
			mov GOOD_SWAP, 1
			mov CLICK_ENABLE, 0
			mov USER_TURN, 1
			mov damage, 0
			mov GAME_STATUS, 3
		.ENDIF
	.ENDIF

	;mov @chessAddress, OFFSET chessboard
	;mov eax, @chessAddress
	;mov eax, [eax]
	;mov @cell, eax
;
	;.IF @cell.m_scale == 0
		;mov eax, 100
		;mov @cell.m_scale, al
	;.ELSE
		;;sub @cell.m_scale, 10
		;mov al, @cell.m_scale
		;div memnum2
		;mov @cell.m_scale, al
	;.ENDIF
	;mov eax, @cell
	;mov chessboard, eax

	INVOKE InvalidateRect, hWnd, NULL, FALSE
	ret

TimerUpdate ENDP
;-------------------


;-----------------------------------------------------
WinProc PROC uses ebx edi esi,
	hWnd:DWORD, localMsg:DWORD, wParam:DWORD, lParam:DWORD
; windows窗口消息处理
;-----------------------------------------------------
	mov eax, localMsg

	.IF eax == WM_PAINT
		; 调用绘图过程
		;.IF REFRESH_PAINT == 1
		INVOKE PaintProc, hWnd, wParam, lParam
		;.ENDIF
	.ELSEIF eax == WM_CREATE
		INVOKE InitLoadProc, hWnd, wParam, lParam
		INVOKE SetTimer, hWnd, TIMER_GAMETIMER, TIMER_GAMETIMER_ELAPSE, NULL
	.ELSEIF eax == WM_LBUTTONDOWN
		; 点击可用
		.IF CLICK_ENABLE == 1
			INVOKE LButtonDownProc, hWnd, wParam, lParam
		.ENDIF
	.ELSEIF eax == WM_CHAR
		.IF UI_STAGE == 2

		.ENDIF

	.ELSEIF eax == WM_TIMER
		INVOKE TimerUpdate, hWnd

	.ELSEIF eax == WM_LBUTTONDOWN		; mouse button?
	  ;INVOKE MessageBox, hWnd, ADDR PopupText,
	    ;ADDR PopupTitle, MB_OK
	  ;jmp WinProcExit
	.ELSEIF eax == WM_QUIT
		INVOKE DeleteObject, hFont
	.ELSEIF eax == WM_DESTROY
        INVOKE PostQuitMessage, 0
	.ELSE		; other message?
	  INVOKE DefWindowProc, hWnd, localMsg, wParam, lParam
	  jmp WinProcExit
	.ENDIF

WinProcExit:
	ret
WinProc ENDP


;-------------------------------------
InitGameProc PROC
; 初始化一局游戏
;-------------------------------------
	INVOKE InitializeBoard
	mov USER1_SCORE, INIT_SCORE
	INVOKE IntToString, USER1_SCORE, ADDR USER1_SCORE_TEXT
	mov USER2_SCORE, INIT_SCORE
	INVOKE IntToString, USER2_SCORE, ADDR USER2_SCORE_TEXT
	mov selectedChessOne, -1
	mov GOOD_SWAP, 1
	mov CLICK_ENABLE, 1
	mov USER_TURN, 0
	mov damage, 0
	mov GAME_STATUS, 0
InitGameProc ENDP

;-----------------------------------------------------
LButtonDownProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; 鼠标左键点击
;-----------------------------------------------------
	local	@mouseX:WORD
	local	@mouseY:WORD
	local	@selected:DWORD
	mov eax, lParam
	mov @mouseX, ax
	sar eax, 16
	mov @mouseY, ax
	.IF UI_STAGE == 0
		movzx eax, @mouseX
		.IF @mouseX >= BUTTON_X && @mouseX <= BUTTON_X + BUTTON_WIDTH
			movzx eax, @mouseY
			.IF eax >= BUTTON_Y1 && eax <= BUTTON_Y1 + BUTTON_HEIGHT
				INVOKE InitGameProc
				mov GAME_MODE, 0
				mov REFRESH_PAINT, 1
				mov UI_STAGE, 1
			.ELSEIF eax >= BUTTON_Y2 && eax <= BUTTON_Y2 + BUTTON_HEIGHT
				mov GAME_MODE, 1
				mov REFRESH_PAINT, 1
				mov UI_STAGE, 2
				INVOKE CreateThread, NULL, NULL, ADDR server_socket, NULL, 0, NULL
			.ELSEIF eax >= BUTTON_Y3 && eax <= BUTTON_Y3 + BUTTON_HEIGHT
				mov GAME_MODE, 1
				mov REFRESH_PAINT, 1
				mov UI_STAGE, 3
			.ENDIF
				
		.ENDIF
	.ELSEIF UI_STAGE == 1
		.IF @mouseX >= WINDOW_WIDTH - RETURN_WIDTH && @mouseY <= RETURN_HEIGHT
			mov UI_STAGE, 0
			ret
		.ENDIF
		movzx eax, @mouseX
		sub eax, CLICK_BOARD_X
		mov edx, 0
		mov ebx, CLICK_CELL_WIDTH
		div ebx
		.IF eax < 9
			mov @selected, eax
			and eax, 1b
			.IF eax == 1
				movzx eax, @mouseY
				sub eax, BOARD_Y
				sub eax, COLUMN_CELL_SPACE
				mov edx, 0
				mov ebx, CLICK_CELL_HEIGHT
				div ebx
				.IF eax < 8
					mov ebx ,18
					mul ebx
					add eax, 9
					add @selected, eax
				.ELSE
					mov @selected, -1
				.ENDIF
			.ELSEIF eax == 0
				movzx eax, @mouseY
				sub eax, BOARD_Y
				mov edx, 0
				mov ebx, CLICK_CELL_HEIGHT
				div ebx
				.IF eax < 9
					mov ebx ,18
					mul ebx
					add @selected, eax
				.ELSE
					mov @selected, -1
				.ENDIF
			.ENDIF
		.ELSE
			mov @selected, -1
		.ENDIF

		.IF @selected == -1 || selectedChessOne == -1
			mov eax, @selected
			mov selectedChessOne, eax
			mov REFRESH_PAINT, 1
		.ELSE
			mov eax, @selected
			sub eax, selectedChessOne
			.IF eax == -18 || eax == -10 || eax == -8 || eax == 8 || eax == 10 || eax == 18
				mov eax, @selected
				mov selectedChessTwo, eax
				mov GOOD_SWAP, 1
				mov GAME_STATUS, 1
				mov CLICK_ENABLE, 0
				mov REFRESH_PAINT, 1
			.ELSE
				mov eax, @selected
				mov selectedChessOne, eax
				mov REFRESH_PAINT, 1
			.ENDIF
		.ENDIF
	.ELSEIF UI_STAGE == 2
		.IF @mouseX >= WINDOW_WIDTH - RETURN_WIDTH && @mouseY <= RETURN_HEIGHT
			mov UI_STAGE, 0
			mov REFRESH_PAINT, 1
			mov quit_flag, 1
			ret
		.ENDIF
	.ELSEIF UI_STAGE == 3
		.IF @mouseX >= WINDOW_WIDTH - RETURN_WIDTH && @mouseY <= RETURN_HEIGHT
			mov UI_STAGE, 0
			mov REFRESH_PAINT, 1
			ret
		.ENDIF

		.IF @mouseX >= BUTTON_X && @mouseX <= BUTTON_X + BUTTON_WIDTH
			movzx eax, @mouseY
			.IF eax >= BUTTON_Y3 && eax <= BUTTON_Y3 + BUTTON_HEIGHT
				INVOKE CreateThread, NULL, NULL, ADDR client_socket, NULL, 0, NULL
				mov UI_STAGE, 1
				mov REFRESH_PAINT, 1
			.ENDIF
				
		.ENDIF
	.ELSEIF UI_STAGE == 10 || UI_STAGE == 20
		.IF @mouseX >= WINDOW_WIDTH - RETURN_WIDTH && @mouseY <= RETURN_HEIGHT
			mov UI_STAGE, 0
			mov REFRESH_PAINT, 1
			ret
		.ENDIF
	.ENDIF

	ret
LButtonDownProc ENDP

;-----------------------------------------------------
PaintProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; 绘制
;-----------------------------------------------------
	local   @ps:PAINTSTRUCT
	local   @blankBmp:HBITMAP
	;local   @hdcWindow:DWORD
	;local   @hdcLoadBmp:DWORD
	local   @hdcMemBuffer:DWORD
	local	@stRect:RECT
	local	@cell:CELL
	local	@i:DWORD
	local	@j:DWORD
	local	@x:DWORD
	local	@y:DWORD
	local	@chessx:DWORD
	local	@chessy:DWORD
	local	@chessw:DWORD
	local	@chessh:DWORD
	local	@chessAddress:DWORD
	local	@chessColor:DWORD

	invoke  BeginPaint,hWnd,addr @ps
	mov hDC,eax
	;INVOKE GdipCreateFromHDC, hDC, OFFSET graphics
	;INVOKE GdipSetSmoothingMode, graphics, SmoothingModeAntiAlias

	invoke CreateCompatibleDC, hDC
	mov @hdcMemBuffer,eax

	INVOKE CreateCompatibleBitmap, hDC, WINDOW_WIDTH, WINDOW_HEIGHT
	mov @blankBmp, eax
	INVOKE SelectObject, @hdcMemBuffer, @blankBmp

	INVOKE GdipCreateFromHDC, @hdcMemBuffer, OFFSET graphics
	INVOKE GdipSetSmoothingMode, graphics, SmoothingModeAntiAlias
	;invoke CreateCompatibleDC, @hdcWindow
	;mov @hdcLoadBmp,eax
	;invoke CreateCompatibleBitmap,@hdcWindow,576,768
	;mov @blankBmp,eax
	;invoke SelectObject,@hdcMemBuffer,@blankBmp

	;INVOKE GdipDrawImageI, graphics, hChessBg, 0, 0
	;INVOKE GdipDrawImageI, graphics, hChessBg, 200, 200

	.IF UI_STAGE == 0
		INVOKE GdipDrawImageI, graphics, hStartUI, 0, 0

		INVOKE GdipDrawImageRectI, graphics, hStartButton1,
						BUTTON_X,					
						BUTTON_Y1,					
						BUTTON_WIDTH, BUTTON_HEIGHT
		INVOKE GdipDrawImageRectI, graphics, hStartButton2,
						BUTTON_X,					
						BUTTON_Y2,					
						BUTTON_WIDTH, BUTTON_HEIGHT
		INVOKE GdipDrawImageRectI, graphics, hStartButton3,
						BUTTON_X,					
						BUTTON_Y3,					
						BUTTON_WIDTH, BUTTON_HEIGHT
		mov REFRESH_PAINT, 0

	.ELSEIF UI_STAGE == 1

		INVOKE GdipDrawImageRectI, graphics, hReturnButton,
						WINDOW_WIDTH - RETURN_WIDTH,					
						0,
						RETURN_WIDTH, RETURN_HEIGHT

		mov @i, 0
		mov @y, BOARD_Y
		.REPEAT
			mov @j, 0
			mov @x, BOARD_X
			mov eax, @i
			AND eax, 1b
			.IF eax == 1
				add @x, EVEN_CELL_START
				.REPEAT
					INVOKE GdipDrawImageRectI, graphics, hChessBg,
						@x,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
						@y,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
						CELL_WIDTH, CELL_HEIGHT
					add @x, ROW_CELL_SPACE
					inc @j

				.UNTIL @j == 4
			.ELSE
				.REPEAT
					INVOKE GdipDrawImageRectI, graphics, hChessBg,
						@x,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
						@y,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
						CELL_WIDTH, CELL_HEIGHT
					add @x, ROW_CELL_SPACE
					inc @j
				.UNTIL @j == 5
			.ENDIF
			add @y, COLUMN_CELL_SPACE	; 行y值
			inc @i
		.UNTIL @i == 17


		mov @i, 0
		mov @y, BOARD_Y
		mov @chessAddress, OFFSET chessboard
		.REPEAT
			mov @j, 0
			mov @x, BOARD_X
			mov eax, @i
			AND eax, 1b
			.IF eax == 1
				add @x, EVEN_CELL_START
				.REPEAT
					mov eax, @chessAddress
					mov eax, [eax]
					mov @cell, eax
					.IF @cell.m_color == 1
						mov eax, hChessType1
					.ELSEIF @cell.m_color == 2
						mov eax, hChessType2
					.ELSEIF @cell.m_color == 3
						mov eax, hChessType3
					.ELSEIF @cell.m_color == 4
						mov eax, hChessType4
					.ELSEIF @cell.m_color == 5
						mov eax, hChessType5
					.ELSEIF @cell.m_color == 6
						mov eax, hChessType6
					.ENDIF
					mov @chessColor, eax


					.IF @cell.m_scale != 128
						mov eax, CHESS_WIDTH
						mul @cell.m_scale
						mov edx, 0
						div memnum128
						mov @chessw, eax
						mov eax, CHESS_HEIGHT
						mul @cell.m_scale
						mov edx, 0
						div memnum128
						mov @chessh, eax
					.ELSEIF
						mov eax, CHESS_WIDTH
						mov @chessw, eax
						mov eax, CHESS_HEIGHT
						mov @chessh, eax
					.ENDIF
					mov eax, CELL_WIDTH
					sub eax, @chessw
					mov edx, 0
					div memnum2
					add eax, @x
					mov @chessx, eax
					mov eax, CELL_HEIGHT
					sub eax, @chessh
					mov edx, 0
					div memnum2
					add eax, @y
					mov @chessy, eax


					INVOKE GdipDrawImageRectI, graphics, @chessColor,
						@chessx,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
						@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
						@chessw, @chessh
					.IF GAME_STATUS == 4
						.IF @cell.m_type == 100 || (@cell.m_type == 1 && @cell.m_newColor == 0)
							INVOKE GdipDrawImageRectI, graphics, hChessBomb,
							@chessx,					; BOARD_X + @j * ROW_CELL_SPACE,
							@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
							@chessw, @chessh
						.ENDIF
					.ELSE
						.IF @cell.m_type == 1
							INVOKE GdipDrawImageRectI, graphics, hChessBomb,
							@chessx,					; BOARD_X + @j * ROW_CELL_SPACE,
							@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
							@chessw, @chessh
						.ENDIF
					.ENDIF
					
					add @x, ROW_CELL_SPACE
					inc @j
					add @chessAddress, 2 * TYPE CELL

				.UNTIL @j == 4
			.ELSE

				.REPEAT
					mov eax, @chessAddress
					mov eax, [eax]
					mov @cell, eax
					.IF @cell.m_color == 1
						mov eax, hChessType1
					.ELSEIF @cell.m_color == 2
						mov eax, hChessType2
					.ELSEIF @cell.m_color == 3
						mov eax, hChessType3
					.ELSEIF @cell.m_color == 4
						mov eax, hChessType4
					.ELSEIF @cell.m_color == 5
						mov eax, hChessType5
					.ELSEIF @cell.m_color == 6
						mov eax, hChessType6
					.ENDIF
					mov @chessColor, eax

					.IF @cell.m_scale != 128
						mov eax, CHESS_WIDTH
						mul @cell.m_scale
						mov edx, 0
						div memnum128
						mov @chessw, eax
						mov eax, CHESS_HEIGHT
						mul @cell.m_scale
						mov edx, 0
						div memnum128
						mov @chessh, eax
					.ELSEIF
						mov eax, CHESS_WIDTH
						mov @chessw, eax
						mov eax, CHESS_HEIGHT
						mov @chessh, eax
					.ENDIF
					mov eax, CELL_WIDTH
					sub eax, @chessw
					mov edx, 0
					div memnum2
					add eax, @x
					mov @chessx, eax
					mov eax, CELL_HEIGHT
					sub eax, @chessh
					mov edx, 0
					div memnum2
					add eax, @y
					mov @chessy, eax

					INVOKE GdipDrawImageRectI, graphics, @chessColor,
						@chessx,					; BOARD_X + @j * ROW_CELL_SPACE,
						@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
						@chessw, @chessh
					.IF GAME_STATUS == 4
						.IF @cell.m_type == 100 || (@cell.m_type == 1 && @cell.m_newColor == 0)
							INVOKE GdipDrawImageRectI, graphics, hChessBomb,
							@chessx,					; BOARD_X + @j * ROW_CELL_SPACE,
							@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
							@chessw, @chessh
						.ENDIF
					.ELSE
						.IF @cell.m_type == 1
							INVOKE GdipDrawImageRectI, graphics, hChessBomb,
							@chessx,					; BOARD_X + @j * ROW_CELL_SPACE,
							@chessy,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
							@chessw, @chessh
						.ENDIF
					.ENDIF
					
					add @x, ROW_CELL_SPACE
					inc @j
					add @chessAddress, 2 * TYPE CELL

				.UNTIL @j == 5
			.ENDIF
			add @y, COLUMN_CELL_SPACE	; 行y值
			inc @i
		.UNTIL @i == 17

		.IF GAME_STATUS == 0
			mov eax, selectedChessOne
			.IF eax != -1
				mov edx, 0
				mov ebx, 9
				div ebx
				mov @j, eax
				mov @i, edx
				mov eax, @i
				mov ebx, ROW_CELL_SPACE_HALF
				mul ebx
				add eax, BOARD_X
				mov @x, eax
				mov eax, @j
				mov ebx, COLUMN_CELL_SPACE
				mul ebx
				add eax, BOARD_Y
				mov @y, eax
				INVOKE GdipDrawImageRectI, graphics, hChessSelected,
							@x,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
							@y,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
							CELL_WIDTH, CELL_HEIGHT

			.ENDIF
			mov REFRESH_PAINT, 0
		.ELSEIF GAME_STATUS == 6
			mov eax, selectedChessOne
			.IF eax != -1
				mov edx, 0
				mov ebx, 9
				div ebx
				mov @j, eax
				mov @i, edx
				mov eax, @i
				mov ebx, ROW_CELL_SPACE_HALF
				mul ebx
				add eax, BOARD_X
				mov @x, eax
				mov eax, @j
				mov ebx, COLUMN_CELL_SPACE
				mul ebx
				add eax, BOARD_Y
				mov @y, eax

				add @x, 20
				mov eax, @x
				mul AIdelay
				mov ecx, eax
				mov ebx, AI_DELAY_FRAME
				sub ebx, AIdelay
				mov eax, CURSOR_MOVE_START_X
				mul ebx
				add ecx, eax
				mov eax, ecx
				mov edx, 0
				mov ebx, AI_DELAY_FRAME
				div ebx
				mov @x, eax

				sub @y, 100
				mov eax, @y
				mul AIdelay
				mov ecx, eax
				mov ebx, AI_DELAY_FRAME
				sub ebx, AIdelay
				mov eax, CURSOR_MOVE_START_Y
				mul ebx
				add ecx, eax
				mov eax, ecx
				mov edx, 0
				mov ebx, AI_DELAY_FRAME
				div ebx
				mov @y, eax


				INVOKE GdipDrawImageI, graphics, hCursor,
							@x,					
							@y			
			.ENDIF
		.ENDIF

		INVOKE GdipDrawImageRectI, graphics, hAvatar,
							USER1_AVATAR_X,
							USER1_AVATAR_Y,
							AVATAR_WIDTH, AVATAR_HEIGHT
		INVOKE GdipDrawImageRectI, graphics, hAvatar,
							USER2_AVATAR_X,
							USER2_AVATAR_Y,
							AVATAR_WIDTH, AVATAR_HEIGHT

		; 绘制分数
		INVOKE SelectObject, @hdcMemBuffer, hFont
		INVOKE SetTextColor, @hdcMemBuffer, 0FFFFFFh ; 产生白色的画笔
		INVOKE SetBkMode, @hdcMemBuffer, TRANSPARENT
		INVOKE TextOut, @hdcMemBuffer, USER1_SCORE_X, USER1_SCORE_Y, ADDR USER1_SCORE_TEXT, USER1_SCORE_TEXT_LEN
		INVOKE TextOut, @hdcMemBuffer, USER2_SCORE_X, USER2_SCORE_Y, ADDR USER2_SCORE_TEXT, USER2_SCORE_TEXT_LEN
	.ELSEIF UI_STAGE == 2
		INVOKE GdipDrawImageI, graphics, hStartUI, 0, 0
		INVOKE GdipDrawImageRectI, graphics, hReturnButton,
				WINDOW_WIDTH - RETURN_WIDTH,					
				0,
				RETURN_WIDTH, RETURN_HEIGHT
		INVOKE GdipDrawImageI, graphics, hWaitDialog,
				DIALOG_X,					
				DIALOG_Y
		; 绘制输入ip
		INVOKE SelectObject, @hdcMemBuffer, hFont
		INVOKE SetTextColor, @hdcMemBuffer, 0FFFFFFh ; 产生白色的画笔
		INVOKE SetBkMode, @hdcMemBuffer, TRANSPARENT
		INVOKE Str_length, ADDR local_ip
		INVOKE TextOut, @hdcMemBuffer, DIALOG_X + 120, DIALOG_Y + 170, ADDR local_ip, eax
		mov REFRESH_PAINT, 0
	.ELSEIF UI_STAGE == 3
		INVOKE GdipDrawImageI, graphics, hStartUI, 0, 0
		INVOKE GdipDrawImageRectI, graphics, hReturnButton,
				WINDOW_WIDTH - RETURN_WIDTH,					
				0,
				RETURN_WIDTH, RETURN_HEIGHT
		INVOKE GdipDrawImageRectI, graphics, hConnectButton,
				BUTTON_X,					
				BUTTON_Y3,					
				BUTTON_WIDTH, BUTTON_HEIGHT
		INVOKE GdipDrawImageI, graphics, hInputDialog,
				DIALOG_X,					
				DIALOG_Y
		; 绘制输入ip
		INVOKE SelectObject, @hdcMemBuffer, hFont
		INVOKE SetTextColor, @hdcMemBuffer, 0FFFFFFh ; 产生白色的画笔
		INVOKE SetBkMode, @hdcMemBuffer, TRANSPARENT
		INVOKE Str_length, ADDR server_ip
		INVOKE TextOut, @hdcMemBuffer, DIALOG_X + 120, DIALOG_Y + 170, ADDR server_ip, eax
		mov REFRESH_PAINT, 0
	.ELSEIF UI_STAGE == 10
		INVOKE GdipDrawImageI, graphics, hStartUI, 0, 0
		INVOKE GdipDrawImageRectI, graphics, hReturnButton,
				WINDOW_WIDTH - RETURN_WIDTH,					
				0,
				RETURN_WIDTH, RETURN_HEIGHT
		INVOKE GdipDrawImageI, graphics, hWinDialog,
				DIALOG_X,					
				DIALOG_Y
		mov REFRESH_PAINT, 0
	.ELSEIF UI_STAGE == 20
		INVOKE GdipDrawImageI, graphics, hStartUI, 0, 0
		INVOKE GdipDrawImageRectI, graphics, hReturnButton,
				WINDOW_WIDTH - RETURN_WIDTH,					
				0,
				RETURN_WIDTH, RETURN_HEIGHT
		INVOKE GdipDrawImageI, graphics, hLoseDialog,
				DIALOG_X,					
				DIALOG_Y
		mov REFRESH_PAINT, 0
	.ENDIF

	INVOKE BitBlt, hDC ,0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, @hdcMemBuffer, 0, 0, SRCCOPY
	invoke GdipDeleteGraphics, graphics
	invoke DeleteDC, @hdcMemBuffer
	invoke DeleteObject, @blankBmp
	;invoke DeleteDC,@hdcLoadBmp
	invoke  EndPaint,hWnd, addr @ps
	ret

PaintProc ENDP


;-----------------------------------------------------
InitLoadProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; 加载资源文件
;-----------------------------------------------------

	INVOKE GdipLoadImageFromFile, OFFSET startUI, ADDR hStartUI

	INVOKE GdipLoadImageFromFile, OFFSET startButton1, ADDR hStartButton1
	INVOKE GdipLoadImageFromFile, OFFSET startButton2, ADDR hStartButton2
	INVOKE GdipLoadImageFromFile, OFFSET startButton3, ADDR hStartButton3

	INVOKE GdipLoadImageFromFile, OFFSET returnButton, ADDR hReturnButton
	INVOKE GdipLoadImageFromFile, OFFSET connectButton, ADDR hConnectButton

	INVOKE GdipLoadImageFromFile, OFFSET inputDialog, ADDR hInputDialog
	INVOKE GdipLoadImageFromFile, OFFSET waitDialog, ADDR hWaitDialog
	INVOKE GdipLoadImageFromFile, OFFSET winDialog, ADDR hWinDialog
	INVOKE GdipLoadImageFromFile, OFFSET loseDialog, ADDR hLoseDialog

	INVOKE GdipLoadImageFromFile, OFFSET chessBg, ADDR hChessBg
	INVOKE GdipLoadImageFromFile, OFFSET chessRed, ADDR hChessType1
	INVOKE GdipLoadImageFromFile, OFFSET chessPurple, ADDR hChessType2
	INVOKE GdipLoadImageFromFile, OFFSET chessGreen, ADDR hChessType3
	INVOKE GdipLoadImageFromFile, OFFSET chessOrange, ADDR hChessType4
	INVOKE GdipLoadImageFromFile, OFFSET chessYellow, ADDR hChessType5
	INVOKE GdipLoadImageFromFile, OFFSET chessBlue, ADDR hChessType6
	INVOKE GdipLoadImageFromFile, OFFSET chessBomb, ADDR hChessBomb
	INVOKE GdipLoadImageFromFile, OFFSET chessSelected, ADDR hChessSelected

	INVOKE GdipLoadImageFromFile, OFFSET avatar, ADDR hAvatar
	INVOKE GdipLoadImageFromFile, OFFSET cursor, ADDR hCursor

	INVOKE CreateFont, 30, 12, 0, 0, FW_BLACK, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_CHARACTER_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_SWISS, addr fontName
	mov	hFont,eax
	ret
InitLoadProc ENDP

;---------------------------------------------------
ErrorHandler PROC
; Display the appropriate system error message.
;---------------------------------------------------
.data
pErrorMsg  DWORD ?		; ptr to error message
messageID  DWORD ?
.code
	;INVOKE GetLastError	; Returns message ID in EAX
	;mov messageID,eax
;
	;; Get the corresponding message string.
	;INVOKE FormatMessage, FORMAT_MESSAGE_ALLOCATE_BUFFER + \
	  ;FORMAT_MESSAGE_FROM_SYSTEM,NULL,messageID,NULL,
	  ;ADDR pErrorMsg,NULL,NULL
;
	;; Display the error message.
	;INVOKE MessageBox,NULL, pErrorMsg, ADDR ErrorTitle,
	  ;MB_ICONERROR+MB_OK
;
	;; Free the error message string.
	;INVOKE LocalFree, pErrorMsg
	ret
ErrorHandler ENDP

END WinMain
