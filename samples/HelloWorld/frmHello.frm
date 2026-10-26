VERSION 5.00
Begin VB.Form Form1 
   Caption         =   "Hello World"
   ClientHeight    =   3090
   ClientLeft      =   60
   ClientTop       =   450
   ClientWidth     =   4680
   LinkTopic       =   "Form1"
   ScaleHeight     =   3090
   ScaleWidth      =   4680
   StartUpPosition =   3  'Windows Default
   Begin VB.TextBox Text1 
      Height          =   315
      Left            =   720
      TabIndex        =   0
      Top             =   600
      Width           =   3255
   End
   Begin VB.CommandButton Command1 
      Caption         =   "Say Hello"
      Height          =   495
      Left            =   1680
      TabIndex        =   1
      Top             =   1200
      Width           =   1335
   End
   Begin VB.Label Label1 
      Caption         =   "Type your name"
      Height          =   315
      Left            =   720
      TabIndex        =   2
      Top             =   2040
      Width           =   3255
   End
End
Attribute VB_Name = "Form1"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Private Sub Form_Load()
    Label1.Caption = "Type your name"
End Sub

Private Sub Command1_Click()
    Label1.Caption = "Hello " & Trim(Text1.Text)
    MsgBox "Hello from VB6CloneIDE!"
End Sub
