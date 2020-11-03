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


TIMER_GAMETIMER equ 1			; ��Ϸ��Ĭ�ϼ�ʱ��ID
TIMER_GAMETIMER_ELAPSE equ 10	; Ĭ�ϼ�ʱ��ˢ�¼���ĺ�����

;==================== DATA =======================
.data

memnum100 DWORD 100
memnum2 DWORD 2

; ���ṹ��
CELL STRUCT
    m_color    BYTE    ?    ;��ɫ
    m_type     BYTE    0    ;��������(0Ϊ��ͨ��1Ϊը��)
    m_frame    BYTE    0    ;֡����
	m_scale    BYTE    0    ;ռλ����4�ֽ�
CELL ENDS

; ����
chessboard CELL 153 dup(<1,0,0,100>)


; win32���
hInstance DWORD ?
hMainWnd  DWORD ?
hDC       DWORD ?


; ���崰�ڽṹ��
MainWin WNDCLASSEX <NULL, NULL, WinProc,NULL,NULL,NULL,NULL,NULL, \
	COLOR_WINDOW,NULL,szClassName, NULL>
msg MSG <>


szWindowName  BYTE "NanoChess",0
szClassName   BYTE "ASMWin",0


; gdip���
m_GdiplusToken	DWORD 0;
graphics		DWORD 0;


; �ļ��������
$$Unicode MACRO name, string
	&name	LABEL BYTE
	FORC	char, string
		DB '&char', 0
	ENDM
		DB 0, 0
ENDM

; pngͼƬ�ļ�
$$Unicode chessBg, png\chessBg.png
$$Unicode chessRed, png\chessRed.png			; type1
$$Unicode chessPurple, png\chessPurple.png		; type2
$$Unicode chessGreen, png\chessGreen.png		; type3
$$Unicode chessOrange, png\chessOrange.png		; type4
$$Unicode chessYellow, png\chessYellow.png		; type5
$$Unicode chessBlue, png\chessBlue.png			; type6


; gdip����ͼƬ��Դָ��
hChessBg  DWORD 0
hChessType1  DWORD 0
hChessType2  DWORD 0
hChessType3  DWORD 0
hChessType4  DWORD 0
hChessType5  DWORD 0
hChessType6  DWORD 0

; proc����
InitLoadProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
PaintProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
InitializeBoard PROTO STDCALL
StartupInput		GdiplusStartupInput <1, NULL, FALSE, 0>

; ��¼����Щ������ɫ�������õı�Ϊ0
possibleColor BYTE 1,2,3,4,5,6					

;------------------------
.code


; ��ȡfirst��second�������ڵ�α�����������eax����
GetRandomInt PROC uses ecx edx first:DWORD, second:DWORD
	invoke GetTickCount ; ȡ����������ӣ�Ҳ���ñ�ķ�������
	mov ecx, 22639      ; X = ecx = 22639
	mul ecx             ; eax = eax * X
	add eax, 38711      ; eax = eax + Y ��Y = 38711��
	mov ecx, second     ; ecx = ����
	sub ecx, first      ; ecx = ���� - ����
	inc ecx             ; Z = ecx + 1 ���õ��˷�Χ��
	xor edx, edx        ; edx = 0
	div ecx             ; eax = eax mod Z ��������edx���棩
	add edx, first      ; ����������������ķ�Χ
	mov eax, edx        ; eax = Rand_Number
	ret
GetRandomInt ENDP

InitializeBoard PROC uses eax ecx edx
	; �����ʼ���������̣�Ҫ����������Ԫ��
	invoke GetTickCount
	invoke nseed, eax
	mov eax, 0
	.WHILE eax < 153
		; ������index = 0 2 4 6 8�ǵ�һ������ 10 12 14 16�ǵڶ������ӣ�����һ��9����
		; �Ӷ�ÿ�����Ӻ���Χ6�����ӵ�index�Ĳ�ֵΪ-18 -10 -8 +8 +10 +18
		; �涨��ɫ��1,2,3,4,5,6����
		; �����ǰ���У�����Ҫ���
		; ���36֮ǰ�Ľڵ㣨��3/4�У�����Ҫ���Ϸ����
		; ���⣬�����ǰ���У�17��9�У���ֻ��Ҫ�����Ϸ������Ϸ����
		; ����ǵ�7/8�У���Ҫ�����Ϻ����Ϸ����
		; ���������Ҫ�����ϡ����ϡ���������������
		mov [possibleColor], 1
		mov [possibleColor + 1], 2
		mov [possibleColor + 2], 3
		mov [possibleColor + 3], 4
		mov [possibleColor + 4], 5
		mov [possibleColor + 5], 6

		push eax
		mov edx, 0
		mov ecx, 9
		div ecx	; ��ȡ��ǰ�ǵڼ��в�����edx��
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
				mov cl, byte ptr [eax]							; ������Ϸ���һ������
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
				mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
				.IF cl == ch
					; �����������������ɫ��ͬ����ֹѡ��������ɫ
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
				.ENDIF
				pop edx
				pop eax
				
				.IF eax >= 36								; 18,28��������ֻ��Ҫ�����ϼ��
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]					; ������Ϸ���һ������
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
					mov ch, byte ptr [eax]					; ������Ϸ��ڶ�������
					.IF cl == ch
						; �����������������ɫ��ͬ����ֹѡ��������ɫ
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al						; ��������ɫ��Ϊ0������ֹѡ��
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
				mov cl, byte ptr [eax]						; ������Ϸ���һ������
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
				mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
				.IF cl == ch
					; �����������������ɫ��ͬ����ֹѡ��������ɫ
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
				.ENDIF
				pop edx
				pop eax

				.IF eax >= 36								; 26,34��������ֻ��Ҫ�����ϼ��
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]							; ������Ϸ���һ������
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
					mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
					.IF cl == ch
						; �����������������ɫ��ͬ����ֹѡ��������ɫ
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
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
				mov cl, byte ptr [eax]							; ������Ϸ���һ������
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
				mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
				.IF cl == ch
					; �����������������ɫ��ͬ����ֹѡ��������ɫ
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
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
				mov cl, byte ptr [eax]							; ������Ϸ���һ������
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
				mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
				.IF cl == ch
					; �����������������ɫ��ͬ����ֹѡ��������ɫ
					mov ch, 0
					add ecx, OFFSET possibleColor
					dec ecx
					mov eax, 0
					mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
				.ENDIF
				pop edx
				pop eax

				.IF eax >= 36								; 26,34��������ֻ��Ҫ�����ϼ��
					push eax
					push edx
					sub eax, 18
					mov ecx, 4
					mul ecx
					add eax, OFFSET chessboard
					mov ecx, 0
					mov cl, byte ptr [eax]							; ������Ϸ���һ������
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
					mov ch, byte ptr [eax]							; ������Ϸ��ڶ�������
					.IF cl == ch
						; �����������������ɫ��ͬ����ֹѡ��������ɫ
						mov ch, 0
						add ecx, OFFSET possibleColor
						dec ecx
						mov eax, 0
						mov [ecx], al							; ��������ɫ��Ϊ0������ֹѡ��
					.ENDIF
					pop edx
					pop eax
				.ENDIF
			.ENDIF
		.ENDIF

		push eax
		mov edx, eax						; ��edx��һ�µ�ǰ���
		mov ecx, 0
		.WHILE ecx == 0						; ѭ��ֱ���ҵ�һ�ֿ�����ɫΪֹ
			;invoke GetRandomInt, 0, 5		; ��ȡһ��0-5֮��������������eax(al)��
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
		mov [eax], cl		; �����ɫ��ʼ��
		pop eax

		add eax, 2	; ��Ч���ӵȼ����±�Ϊż��
	.ENDW
	ret
InitializeBoard ENDP
;-----------------------
WinMain PROC
; windows���ڳ�����ں���
;--------------

	; ��õ�ǰ������
	INVOKE GetModuleHandle, NULL
	mov hInstance, eax
	mov MainWin.hInstance, eax

	mov MainWin.cbSize, sizeof WNDCLASSEX
	mov MainWin.style, CS_HREDRAW or CS_VREDRAW

	; ��ȡͼ��͹��
	INVOKE LoadIcon, NULL, IDI_APPLICATION
	mov MainWin.hIcon, eax
	INVOKE LoadCursor, NULL, IDC_ARROW
	mov MainWin.hCursor, eax

	;mov MainWin.cbSize, sizeof WNDCLASSEX
	;mov MainWin.style, CS_HREDRAW or CS_VREDRAW
	mov MainWin.hbrBackground, COLOR_MENUTEXT + 1

	; ע�ᴰ��
	INVOKE RegisterClassEx, ADDR MainWin
	.IF eax == 0
	  ;call ErrorHandler
	  jmp Exit_Program
	.ENDIF

	; ��ʼ��GDI+
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

;-----------------------------------------------------
WinProc PROC uses ebx edi esi,
	hWnd:DWORD, localMsg:DWORD, wParam:DWORD, lParam:DWORD
; windows������Ϣ����
;-----------------------------------------------------
	mov eax, localMsg

	.IF eax == WM_PAINT
		; ���û�ͼ����
		INVOKE PaintProc, hWnd, wParam, lParam
		INVOKE SetTimer, hWnd, TIMER_GAMETIMER, TIMER_GAMETIMER_ELAPSE, NULL
		
	.ELSEIF eax == WM_CREATE
		INVOKE InitLoadProc, hWnd, wParam, lParam

	.ELSEIF eax == WM_TIMER
		INVOKE InvalidateRect, hWnd, NULL, FALSE

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
; ����
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
	INVOKE GdipCreateFromHDC, hDC, OFFSET graphics
	INVOKE GdipSetSmoothingMode, graphics, SmoothingModeAntiAlias

	;invoke CreateCompatibleDC, @hdcWindow
	;mov @hdcMemBuffer,eax
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
		add @y, COLUMN_CELL_SPACE	; ��yֵ
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
		add @y, COLUMN_CELL_SPACE	; ��yֵ
		inc @i
	.UNTIL @i == 17

	;invoke DeleteObject,@hFont
	;invoke DeleteDC,@hdcMemBuffer
	;invoke DeleteDC,@hdcLoadBmp
	invoke  EndPaint,hWnd,addr @ps
	ret

PaintProc ENDP


;-----------------------------------------------------
InitLoadProc PROC,
	hWnd:DWORD, wParam:DWORD, lParam:DWORD
; ������Դ�ļ�
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
