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

.const
Column equ 9
Row equ 17
boardsize equ 153 ;9 * (2 * 9 - 1) 
WINDOW_WIDTH equ 600
WINDOW_HEIGHT equ 900
WINDOW_TITLEBARHEIGHT equ 32

BOARD_X equ 6
BOARD_Y equ 110

CELL_HEIGHT equ 76
COLUMN_CELL_SPACE equ 38
CELL_WIDTH equ 84
; HALF_CELL_WIDTH equ
EVEN_CELL_START equ 63
ROW_CELL_SPACE equ 126
;chessBg equ BMP_CHESSBG

;==================== DATA =======================
.data

; 棋格结构体
CELL STRUCT
    m_color    BYTE    ?    ;颜色
    m_type     BYTE    0    ;道具类型(0为普通格，1为炸弹)
    m_frame    BYTE    0    ;帧动画
	m_scale    BYTE    0    ;占位，凑4字节
CELL ENDS

; 棋盘
chessboard CELL 153 dup(<1,0,0,1>)


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
$$Unicode chessRed, png\chessRed.png			; type0
$$Unicode chessPurple, png\chessPurple.png		; type1


; gdip加载图片资源指针
hChessBg  DWORD 0
hChessType0  DWORD 0
hChessType1  DWORD 0
hChessType2  DWORD 0
hChessType3  DWORD 0
hChessType4  DWORD 0
hChessType5  DWORD 0

; proc声明
InitLoadProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
PaintProc PROTO STDCALL hWnd:DWORD, wParam:DWORD, lParam:DWORD
StartupInput		GdiplusStartupInput <1, NULL, FALSE, 0>

;------------------------
.code


;-----------------------
WinMain PROC
; windows窗口程序入口函数
;--------------
	
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
	INVOKE DispatchMessage, ADDR msg
    jmp Message_Loop

Exit_Program:
	  INVOKE ExitProcess,0
	  ret
WinMain ENDP

;-----------------------------------------------------
WinProc PROC uses ebx edi esi,
	hWnd:DWORD, localMsg:DWORD, wParam:DWORD, lParam:DWORD
; windows窗口消息处理
;-----------------------------------------------------
	mov eax, localMsg

	.IF eax == WM_PAINT
		; 调用绘图过程
		INVOKE PaintProc, hWnd, wParam, lParam
		
	.ELSEIF eax == WM_CREATE
		INVOKE InitLoadProc, hWnd, wParam, lParam


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
				.IF @cell.m_color == 0
					mov eax, hChessType0
				.ELSEIF @cell.m_color == 1
					mov eax, hChessType1
				.ENDIF
				mov @chessColor, eax

				INVOKE GdipDrawImageRectI, graphics, @chessColor,
					@x,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
					@y,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
					CELL_WIDTH, CELL_HEIGHT
				
				add @x, ROW_CELL_SPACE
				inc @j
				add @chessAddress, 2 * TYPE CELL

			.UNTIL @j == 4
		.ELSE

			.REPEAT
				mov eax, @chessAddress
				mov eax, [eax]
				mov @cell, eax
				.IF @cell.m_color == 0
					mov eax, hChessType0
				.ELSEIF @cell.m_color == 1
					mov eax, hChessType1
				.ENDIF
				mov @chessColor, eax

				INVOKE GdipDrawImageRectI, graphics, @chessColor,
					@x,					; BOARD_X + EVEN_CELL_START + @j * ROW_CELL_SPACE,
					@y,					; BOARD_Y + @i * COLUMN_CELL_SPACE,
					CELL_WIDTH, CELL_HEIGHT
				
				add @x, ROW_CELL_SPACE
				inc @j
				add @chessAddress, 2 * TYPE CELL

			.UNTIL @j == 5
		.ENDIF
		add @y, COLUMN_CELL_SPACE	; 行y值
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
; 加载资源文件
;-----------------------------------------------------
	INVOKE GdipLoadImageFromFile, OFFSET chessBg, ADDR hChessBg
	INVOKE GdipLoadImageFromFile, OFFSET chessRed, ADDR hChessType0
	INVOKE GdipLoadImageFromFile, OFFSET chessPurple, ADDR hChessType1
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
