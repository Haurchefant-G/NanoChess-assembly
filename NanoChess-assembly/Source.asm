TITLE Windows Application                   (WinApp.asm)
.386
.model flat,stdcall
option casemap:none
.stack 4096
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
include	 imm32.inc
includelib  imm32.lib
include	 msimg32.inc
includelib  msimg32.lib
include masm32.inc
includelib  masm32.lib

.const
Column equ 9
Row equ 17
boardsize equ 153 ;9 * (2 * 9 - 1) 
WINDOW_WIDTH equ 600
WINDOW_HEIGHT equ 900
WINDOW_TITLEBARHEIGHT equ 32

BOARD_X equ 6
BOARD_Y equ 110

CELL_WIDTH equ 84
CELL_HEIGHT equ 76
ROW_CELL_SPACE equ 126
COLUMN_CELL_SPACE equ 38
CHESS_WIDTH equ 66
CHESS_HEIGHT equ 60

; HALF_CELL_WIDTH equ
EVEN_CELL_START equ 63
;chessBg equ BMP_CHESSBG


TIMER_GAMETIMER equ 1			; 游戏的默认计时器ID
TIMER_GAMETIMER_ELAPSE equ 10	; 默认计时器刷新间隔的毫秒数

;==================== DATA =======================
.data

memnum100 DWORD 100
memnum2 DWORD 2

; 棋格结构体
CELL STRUCT
    m_color    BYTE    ?    ;颜色
    m_type     BYTE    0    ;道具类型(0为普通格，1为炸弹)
    m_frame    BYTE    0    ;帧动画
	m_scale    BYTE    0    ;占位，凑4字节
CELL ENDS

; 棋盘
chessboard CELL 153 dup(<1,0,0,100>)

; 棋盘信息
cell_size DWORD 4
row_num DWORD 17
col_num DWORD 9
dir_num DWORD 6

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

; png图片文件
$$Unicode chessBg, png\chessBg.png
$$Unicode chessRed, png\chessRed.png			; type1
$$Unicode chessPurple, png\chessPurple.png		; type2
$$Unicode chessGreen, png\chessGreen.png		; type3
$$Unicode chessOrange, png\chessOrange.png		; type4
$$Unicode chessYellow, png\chessYellow.png		; type5
$$Unicode chessBlue, png\chessBlue.png			; type6


; gdip加载图片资源指针
hChessBg  DWORD 0
hChessType1  DWORD 0
hChessType2  DWORD 0
hChessType3  DWORD 0
hChessType4  DWORD 0
hChessType5  DWORD 0
hChessType6  DWORD 0

; proc声明
InitLoadProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
PaintProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
InitializeBoard PROTO STDCALL
StartupInput		GdiplusStartupInput <1, NULL, FALSE, 0>

; 记录有哪些可用颜色，不可用的标为0
possibleColor BYTE 1,2,3,4,5,6					

;------------------------
.code


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
	mov @count, 0
	mov @bonus_count, 0
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
	.endif
	.if @bonus_count > 0
		add eax, 300
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
						INVOKE Cal_address, edx, @row, @col
						mov eax, [eax]
						mov @chess_1, eax
						INVOKE Cal_address, edx, @target_row, @target_col
						mov eax, [eax]
						mov @chess_2, eax
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

;-----------------------
WinMain PROC
; windows窗口程序入口函数
;--------------
	; 播放音乐
	invoke mciSendString, ADDR playSongCommand, NULL, 0, NULL;

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

	INVOKE InitializeBoard


; Begin the program's message-handling loop.
Message_Loop:
	; Get next message from the queue.
	INVOKE GetMessage, ADDR msg, NULL,NULL,NULL

	; Quit if no more messages.
	.IF eax == 0
	  jmp Exit_Program
	.ENDIF

	; Relay the message to the program's WinProc.
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
	local	@cell:CELL
	local	@chessAddress:DWORD
	mov @chessAddress, OFFSET chessboard
	mov eax, @chessAddress
	mov eax, [eax]
	mov @cell, eax

	.IF @cell.m_scale == 0
		mov eax, 100
		mov @cell.m_scale, al
	.ELSE
		sub @cell.m_scale, 10
	.ENDIF
	mov eax, @cell
	mov chessboard, eax

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
		INVOKE PaintProc, hWnd, wParam, lParam
		INVOKE SetTimer, hWnd, TIMER_GAMETIMER, TIMER_GAMETIMER_ELAPSE, NULL
		
	.ELSEIF eax == WM_CREATE
		INVOKE InitLoadProc, hWnd, wParam, lParam

	.ELSEIF eax == WM_TIMER
		INVOKE TimerUpdate, hWnd

	.ELSEIF eax == WM_LBUTTONDOWN		; mouse button?
	  ;INVOKE MessageBox, hWnd, ADDR PopupText,
	    ;ADDR PopupTitle, MB_OK
	  ;jmp WinProcExit
	.ELSE		; other message?
	  INVOKE DefWindowProc, hWnd, localMsg, wParam, lParam
	  jmp WinProcExit
	.ENDIF

WinProcExit:
	ret
WinProc ENDP

;-----------------------------------------------------
PaintProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; 绘制
;-----------------------------------------------------
	local   @ps:PAINTSTRUCT
	local   @blankBmp:HBITMAP
	local   @hdcWindow:DWORD
	local   @hdcLoadBmp:DWORD
	local   @hdcMemBuffer:DWORD
	local	@stRect:RECT
	local	@hFont
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


				.IF @cell.m_scale != 100
					mov eax, CHESS_WIDTH
					mul @cell.m_scale
					mov edx, 0
					div memnum100
					mov @chessw, eax
					mov eax, CHESS_HEIGHT
					mul @cell.m_scale
					mov edx, 0
					div memnum100
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

				.IF @cell.m_scale != 100
					mov eax, CHESS_WIDTH
					mul @cell.m_scale
					mov edx, 0
					div memnum100
					mov @chessw, eax
					mov eax, CHESS_HEIGHT
					mul @cell.m_scale
					mov edx, 0
					div memnum100
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
				
				add @x, ROW_CELL_SPACE
				inc @j
				add @chessAddress, 2 * TYPE CELL

			.UNTIL @j == 5
		.ENDIF
		add @y, COLUMN_CELL_SPACE	; 行y值
		inc @i
	.UNTIL @i == 17

	INVOKE BitBlt, hDC ,0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, @hdcMemBuffer, 0, 0, SRCCOPY
	;invoke DeleteObject,@hFont
	invoke DeleteDC, @hdcMemBuffer
	;invoke DeleteDC,@hdcLoadBmp
	invoke  EndPaint,hWnd,addr @ps
	ret

PaintProc ENDP


;-----------------------------------------------------
InitLoadProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; 加载资源文件
;-----------------------------------------------------
	INVOKE GdipLoadImageFromFile, OFFSET chessBg, ADDR hChessBg
	INVOKE GdipLoadImageFromFile, OFFSET chessRed, ADDR hChessType1
	INVOKE GdipLoadImageFromFile, OFFSET chessPurple, ADDR hChessType2
	INVOKE GdipLoadImageFromFile, OFFSET chessGreen, ADDR hChessType3
	INVOKE GdipLoadImageFromFile, OFFSET chessOrange, ADDR hChessType4
	INVOKE GdipLoadImageFromFile, OFFSET chessYellow, ADDR hChessType5
	INVOKE GdipLoadImageFromFile, OFFSET chessBlue, ADDR hChessType6
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
