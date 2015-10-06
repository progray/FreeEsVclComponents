{******************************************************************************}
{                             ESComponents for VCL                             }
{                            ErrorSoft(c) 2011-2015                            }
{                                                                              }
{            errorsoft@mail.ch | errorsoft-demoscene.narod.ru                  }
{ errorsoft@protonmail.ch | github.com/errorcalc | habrahabr.ru/user/error1024 }
{******************************************************************************}

// This is crap code xD
// You perform risk when use this code

unit ES.Vcl.BaseControls;

{$IF CompilerVersion >= 21}
{$DEFINE VER210UP}
{$ENDIF}

interface

uses
  Windows, Types, Classes, Controls,
  Graphics, Themes, Messages, Uxtheme, Forms;

const
  CM_ESBASE = CM_BASE + $0800;

  CM_PARENT_BUFFEREDCHILDRENS_CHANGED = CM_ESBASE + 1;

type
  TEsCustomControl = class(TWinControl)
  private
    FCanvas: TCanvas;
    CacheBitmap: HBITMAP;// Cache for buffer BitMap
    CacheBackground: HBITMAP;// Cache for background BitMap
    FCachedBuffer: Boolean;
    FCachedBackground: Boolean;
    StoredCachedBuffer: Boolean;
    StoredCachedBackground: Boolean;
    FIsDrawHelper: Boolean;
    FIsOpaque: Boolean;
    FBufferedChildrens: Boolean;
    FParentBufferedChildrens: Boolean;
    FIsTransparentMouse: Boolean;
    // paint
    procedure SetCachedBuffer(Value: Boolean);
    procedure SetCachedBackground(Value: Boolean);
    procedure SetIsDrawHelper(const Value: Boolean);
    procedure SetIsOpaque(const Value: Boolean);
    procedure SetBufferedChildrens(const Value: Boolean);
    procedure SetParentBufferedChildrens(const Value: Boolean);
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMWindowPosChanged(var Message: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    procedure CMParentBufferedChildrensChanged(var Message: TMessage); message CM_PARENT_BUFFEREDCHILDRENS_CHANGED;
    procedure PaintHandler(var Message: TWMPaint);
    // Intercept Mouse
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    // other
    procedure CMTextChanged(var Message: TMessage); message CM_TEXTCHANGED;
    procedure WMTextChanges(var Message: TMessage); message WM_SETTEXT;
    function IsBufferedChildrensStored: Boolean;
  protected
    // paint
    property Canvas: TCanvas read FCanvas;
    procedure DeleteCache;{$IFDEF VER210UP}inline;{$ENDIF}
    procedure Paint; virtual;
    procedure BeginCachedBuffer;{$IFDEF VER210UP}inline;{$ENDIF}
    procedure EndCachedBuffer;{$IFDEF VER210UP}inline;{$ENDIF}
    procedure BeginCachedBackground;{$IFDEF VER210UP}inline;{$ENDIF}
    procedure EndCachedBackground;{$IFDEF VER210UP}inline;{$ENDIF}
    procedure PaintWindow(DC: HDC); override;
    // other
    procedure UpdateText; dynamic;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure PaintTo(DC: HDC; X, Y: Integer);
    procedure UpdateBackground(Repaint: Boolean); overload;
    procedure UpdateBackground; overload;
    property DoubleBuffered default False;
    property ParentDoubleBuffered default False;
  published
    property ParentBackground default True;
    // !!
    property ParentBufferedChildrens: Boolean read FParentBufferedChildrens write SetParentBufferedChildrens default True;
    property BufferedChildrens: Boolean read FBufferedChildrens write SetBufferedChildrens stored IsBufferedChildrensStored;
    // !!
    property CachedBuffer: Boolean read FCachedBuffer write SetCachedBuffer default False;
    property CachedBackground: Boolean read FCachedBackground write SetCachedBackground default False;
    property IsDrawHelper: Boolean read FIsDrawHelper write SetIsDrawHelper default False;
    property IsOpaque: Boolean read FIsOpaque write SetIsOpaque default False;
    property IsTransparentMouse: Boolean read FIsTransparentMouse write FIsTransparentMouse default False;
  end;

implementation

uses
  SysUtils;

type
  THackCtrl = class(TWinControl)
  public
    property BorderWidth;
  end;

function IsStyledClientControl(Control: TControl): Boolean;
begin
  Result := False;

  {$IFDEF VER210UP}
  if Control = nil then
    Exit;

  if StyleServices.Enabled then
  begin
    Result := (seClient in Control.StyleElements) and TStyleManager.IsCustomStyleActive;
  end;
  {$ENDIF}
end;

procedure DrawParentImage(Control: TControl; DC: HDC; InvalidateParent: Boolean = False);
var
  P: TPoint;
  SaveIndex, BorderWidth: Integer;
begin
  if Control.Parent = nil then
    Exit;
  SaveIndex := SaveDC(DC);
  GetViewportOrgEx(DC, P);

  if {(Control is TWinControl) and }(THackCtrl(Control).BorderWidth <> 0) then
  begin
    BorderWidth := THackCtrl(Control).BorderWidth;
    SetViewportOrgEx(DC, P.X - Control.Left - BorderWidth, P.Y - Control.Top - BorderWidth, nil);
  end
  else
    SetViewportOrgEx(DC, P.X - Control.Left, P.Y - Control.Top, nil);

  IntersectClipRect(DC, 0, 0, Control.Parent.ClientWidth, Control.Parent.ClientHeight);

  Control.Parent.Perform(WM_ERASEBKGND, DC, 0);
  //Control.Parent.Perform(WM_PAINT, DC, 0);
  Control.Parent.Perform(WM_PRINTCLIENT, DC, prf_Client);

  RestoreDC(DC, SaveIndex);

  if InvalidateParent then
    if not (Control.Parent is TCustomControl) and not (Control.Parent is TCustomForm) and
       not (csDesigning in Control.ComponentState)and not (Control.Parent is TEsCustomControl) then
    begin
      Control.Parent.Invalidate;
    end;

  SetViewportOrgEx(DC, P.X, P.Y, nil);
end;

{ TESCustomControl }

procedure BitMapDeleteAndNil(var BitMap: HBITMAP);{$IFDEF VER210UP}inline;{$ENDIF}
begin
  if BitMap <> 0 then
  begin
    DeleteObject(BitMap);
    BitMap := 0;
  end;
end;

procedure TEsCustomControl.BeginCachedBackground;
begin
  if CacheBackground <> 0 then BitMapDeleteAndNil(CacheBackground);
  StoredCachedBackground := FCachedBackground;
  FCachedBackground := True;
end;

procedure TEsCustomControl.BeginCachedBuffer;
begin
  if CacheBitmap <> 0 then BitMapDeleteAndNil(CacheBitmap);
  StoredCachedBuffer := FCachedBuffer;
  FCachedBuffer := True;
end;

procedure TEsCustomControl.CMParentBufferedChildrensChanged(var Message: TMessage);
begin
  if FParentBufferedChildrens then
  begin
    if Parent <> nil then
    begin
      if Parent is TEsCustomControl then
        BufferedChildrens := TEsCustomControl(Parent).BufferedChildrens
      else
        BufferedChildrens := False;
    end;
    FParentBufferedChildrens := True;
  end;
end;

procedure TEsCustomControl.CMTextChanged(var Message: TMessage);
begin
  inherited;
  UpdateText;
end;

procedure TEsCustomControl.WMTextChanges(var Message: TMessage);
begin
  Inherited;
  UpdateText;
end;


constructor TEsCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCanvas := TControlCanvas.Create;
  TControlCanvas(FCanvas).Control := Self;
  ControlStyle := ControlStyle - [csOpaque];

  ParentDoubleBuffered := False;
  ParentBackground := True;// ?
  FParentBufferedChildrens := True;// !!
  CacheBitmap := 0;
  CacheBackground := 0;
  FCachedBuffer := False;
  FCachedBackground := False;
end;

procedure TEsCustomControl.DeleteCache;
begin
  if CacheBitmap <> 0 then BitMapDeleteAndNil(CacheBitmap);
  if CacheBackground <> 0 then BitMapDeleteAndNil(CacheBackground);
end;

destructor TEsCustomControl.Destroy;
begin
  FCanvas.Free;
  // ������� ���, ���� �� ����
  DeleteCache;
  inherited;
end;

procedure TEsCustomControl.EndCachedBackground;
begin
  FCachedBackground := StoredCachedBackground;
end;

procedure TEsCustomControl.EndCachedBuffer;
begin
  FCachedBuffer := StoredCachedBuffer;
end;

procedure TEsCustomControl.Paint;
begin
  // for Design time
  if IsDrawHelper and(csDesigning in ComponentState) then
  begin
    SetBkColor(Canvas.Handle, RGB(127,255,255));
    DrawFocusRect(Canvas.Handle, Self.ClientRect);
  end;
end;

// Main crap located here:
{ TODO -cCRITICAL : 22.02.2013:
 Perhaps in this method double buffering has errors
 need test this and eliminate duplication of code!!! }
procedure TEsCustomControl.PaintHandler(var Message: TWMPaint);
var
  PS: TPaintStruct;
  BufferDC: HDC;
  BufferBitMap: HBITMAP;
  UpdateRect: TRect;
  SaveViewport: TPoint;
  Region: HRGN;
  DC: HDC;
  IsBeginPaint: Boolean;
begin
  BufferBitMap := 0;
  Region := 0;
  IsBeginPaint := Message.DC = 0;

  if IsBeginPaint then
  begin
    DC := BeginPaint(Handle, PS);
    {$IFDEF VER210UP}
    if TStyleManager.IsCustomStyleActive and not FCachedBuffer then
      UpdateRect := ClientRect
      // I had to use a crutch to ClientRect, due to the fact that
      // VCL.Styles.TCustomStyle.DoDrawParentBackground NOT use relative coordinates,
      // ie ignores SetViewportOrgEx!
      // This function uses ClientToScreen and ScreenToClient for coordinates calculation!
    else
    {$endif}
      UpdateRect := PS.rcPaint;
  end
  else
  begin
    DC := Message.DC;
    {$IFDEF VER210UP}
    if TStyleManager.IsCustomStyleActive and not FCachedBuffer then
      UpdateRect := ClientRect
    else
    {$endif}
      if GetClipBox(DC, UpdateRect) = ERROR then
        UpdateRect := ClientRect;
  end;

  //------------------------------------------------------------------------------------------------
  // Dublicate code, see PaintWindow
  //------------------------------------------------------------------------------------------------
  // if control not double buffered then create or assign buffer
  if not DoubleBuffered then
  begin
    BufferDC := CreateCompatibleDC(DC);
    // CreateCompatibleDC(DC) return 0 if Drawing takes place to MemDC(buffer):
    // return <> 0 => need to double buffer || return = 0 => no need to double buffer
    if BufferDC <> 0 then
    begin
      // Using the cache if possible
      if FCachedBuffer then
      begin
        // Create cache if need
        if CacheBitmap = 0 then
          CacheBitmap := CreateCompatibleBitmap(DC, ClientWidth, ClientHeight);
        // Assign cache
        BufferBitMap := CacheBitmap;
        // Assign region for minimal overdraw
        Region := CreateRectRgnIndirect(UpdateRect);//0, 0, UpdateRect.Width, UpdateRect.Height);
        SelectClipRgn(BufferDC, Region);
      end
      else
        // Create buffer
        BufferBitMap := CreateCompatibleBitmap(DC, UpdateRect.Width, UpdateRect.Height);
      // Select buffer bitmap
      SelectObject(BufferDC, BufferBitMap);
      // [change coord], if need
      // Moving update region to the (0,0) point
      if not FCachedBuffer then
      begin
        GetViewportOrgEx(BufferDC, SaveViewport);
        SetViewportOrgEx(BufferDC, -UpdateRect.Left + SaveViewport.X, -UpdateRect.Top + SaveViewport.Y, nil);
      end;
    end
    else
      BufferDC := DC;
  end
  else
    BufferDC := DC;
  //------------------------------------------------------------------------------------------------

  // DEFAULT HANDLER:
  Message.DC := BufferDC;
  inherited PaintHandler(Message);

  //------------------------------------------------------------------------------------------------
  // Dublicate code, see PaintWindow
  //------------------------------------------------------------------------------------------------
  // draw to window
  if not DoubleBuffered then
  begin
    if not FCachedBuffer then
    begin
      // [restore coord], if need
      SetViewportOrgEx(BufferDC, SaveViewport.X, SaveViewport.Y, nil);
      BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC, 0, 0, SRCCOPY);
    end
    else
    begin
      BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC,
        UpdateRect.Left, UpdateRect.Top, SRCCOPY);
      DeleteObject(Region);
    end;
    DeleteDC(BufferDC);
  end;

  // delete buufer, if need
  if not FCachedBuffer and (BufferBitMap <> 0) then
    DeleteObject(BufferBitMap);
  //------------------------------------------------------------------------------------------------

  // end paint, if need
  if IsBeginPaint then
    EndPaint(Handle, PS);
end;

procedure TEsCustomControl.PaintTo(DC: HDC; X, Y: Integer);
begin
  if DoubleBuffered then
    FillRect(DC, Rect(0, 0, Width, Height), Brush.Handle);
  inherited PaintTo(DC, X, Y);
end;

{$REGION 'BACKUP'}
(*
// Main crap located here:
procedure TESCustomControl.PaintWindow(DC: HDC);
var
  BufferDC, TempDC: HDC;
  BufferBitMap: HBITMAP;
  UpdateRect: TRect;
  SaveViewport: TPoint;
  Region: HRGN;
begin
  //UpdateRect := Rect(0, 0, Width, Height);
  //GetClipBox(DC, UpdateRect);
  if GetClipBox(DC, UpdateRect) = ERROR then
    UpdateRect := Rect(0, 0, Width, Height);

  if not DoubleBuffered then
  begin
    BufferDC := CreateCompatibleDC(DC);
    // for bitmap context
    if BufferDC = 0 then
      BufferDC := DC
    else
    begin
      if FCachedBuffer then
      begin
        if CacheBuffer = 0 then
          CacheBuffer := CreateCompatibleBitmap(DC, Width, Height);
        BufferBitMap := CacheBuffer;
        Region := CreateRectRgn(0, 0, UpdateRect.Width, UpdateRect.Height);
        SelectClipRgn(BufferDC, Region);
      end
      else
        BufferBitMap := CreateCompatibleBitmap(DC, UpdateRect.Width, UpdateRect.Height);
      SelectObject(BufferDC, BufferBitMap);
    end;
  end
  else
    BufferDC := DC;

  // change coord
  if (not DoubleBuffered){ and (not FCachedBuffer)} then
  begin
    GetViewportOrgEx(BufferDC, SaveViewport);
    SetViewportOrgEx(BufferDC, -UpdateRect.Left + SaveViewport.X, -UpdateRect.Top + SaveViewport.Y, nil);
  end;

  if not(csOpaque in ControlStyle) then
    if ParentBackground then
    begin
      if FCachedBackground then
      begin
        if CacheBackground = 0 then
        begin
          TempDC := CreateCompatibleDC(DC);
          CacheBackground := CreateCompatibleBitmap(DC, Width, Height);
          SelectObject(TempDC, CacheBackground);
          DrawParentImage(Self, TempDC, False);
          DeleteDC(TempDC);
        end;
        TempDC := CreateCompatibleDC(BufferDC);
        SelectObject(TempDC, CacheBackground);
        BitBlt(BufferDC, 0, 0, UpdateRect.Width, UpdateRect.Height, TempDC, 0, 0, SRCCOPY);
        DeleteDC(TempDC);
      end
      else
        DrawParentImage(Self, BufferDC, False);
    end else
      if (not DoubleBuffered) then
        FillRect(BufferDC, Rect(0, 0, Width, Height), Brush.Handle);

  FCanvas.Lock;
  try
    Canvas.Handle := BufferDC;
    TControlCanvas(Canvas).UpdateTextFlags;
    Paint;
    //Canvas.Brush.Color := Random(256*256*256);
    //Canvas.FillRect(Updaterect);
  finally
    FCanvas.Handle := 0;
    FCanvas.Unlock;
  end;

  if IsDrawHelper and(csDesigning in ComponentState) then
  begin
    SetBkColor(BufferDC, RGB(127,255,255));
    DrawFocusRect(BufferDC, self.ClientRect);//self.ClientRect);// for Design
  end;

  // restore coord
  if (not DoubleBuffered){ and (not FCachedBuffer)} then
    SetViewportOrgEx(BufferDC, SaveViewport.X, SaveViewport.Y, nil);

  if not DoubleBuffered then
  begin
    if not FCachedBuffer then
      BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC, 0, 0, SRCCOPY)
    else
    begin
      //BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC, UpdateRect.Left, UpdateRect.Top, SRCCOPY);
      BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC, 0, 0, SRCCOPY);
      DeleteObject(Region);
    end;
    DeleteDC(BufferDC);
  end;

  if not FCachedBuffer and (BufferBitMap <> 0) then DeleteObject(BufferBitMap);
end;
*)
{$ENDREGION}

{ TODO -cMAJOR : 22.02.2013:
 See: PaintHandler,
 need eliminate duplication of code!!! }
procedure TEsCustomControl.PaintWindow(DC: HDC);
var
  TempDC: HDC;
  UpdateRect: TRect;
  //---
  BufferDC: HDC;
  BufferBitMap: HBITMAP;
  Region: HRGN;
  SaveViewport: TPoint;
  BufferedThis: Boolean;
begin
  BufferBitMap := 0;
  Region := 0;

  if GetClipBox(DC, UpdateRect) = ERROR then
    UpdateRect := ClientRect;// Rect(0, 0, Width, Height);

  BufferedThis := not BufferedChildrens;

  if BufferedThis then
  begin
  //------------------------------------------------------------------------------------------------
  // Dublicate code, see PaintHandler
  //------------------------------------------------------------------------------------------------
    // if control not double buffered then create or assign buffer
    if not DoubleBuffered then
    begin
      BufferDC := CreateCompatibleDC(DC);
      // CreateCompatibleDC(DC) return 0 if Drawing takes place to MemDC(buffer):
      // return <> 0 => need to double buffer || return = 0 => no need to double buffer
      if BufferDC <> 0 then
      begin
        // Using the cache if possible
        if FCachedBuffer then
        begin
          // Create cache if need
          if CacheBitmap = 0 then
            CacheBitmap := CreateCompatibleBitmap(DC, ClientWidth, ClientHeight);
          // Assign cache
          BufferBitMap := CacheBitmap;
          // Assign region for minimal overdraw
          Region := CreateRectRgnIndirect(UpdateRect);//0, 0, UpdateRect.Width, UpdateRect.Height);
          SelectClipRgn(BufferDC, Region);
        end
        else
          // Create buffer
          BufferBitMap := CreateCompatibleBitmap(DC, UpdateRect.Width, UpdateRect.Height);
        // Select buffer bitmap
        SelectObject(BufferDC, BufferBitMap);
        // [change coord], if need
        // Moving update region to the (0,0) point
        if not FCachedBuffer then
        begin
          GetViewportOrgEx(BufferDC, SaveViewport);
          SetViewportOrgEx(BufferDC, -UpdateRect.Left + SaveViewport.X, -UpdateRect.Top + SaveViewport.Y, nil);
        end;
      end
      else
        BufferDC := DC;
    end
    else
      BufferDC := DC;
  //------------------------------------------------------------------------------------------------
  end else
    BufferDC := DC;

  if not(csOpaque in ControlStyle) then
    if ParentBackground then
    begin
      if FCachedBackground then
      begin
        if CacheBackground = 0 then
        begin
          TempDC := CreateCompatibleDC(DC);
          CacheBackground := CreateCompatibleBitmap(DC, ClientWidth, ClientHeight);
          SelectObject(TempDC, CacheBackground);
          DrawParentImage(Self, TempDC, False);
          DeleteDC(TempDC);
        end;
        TempDC := CreateCompatibleDC(BufferDC);
        SelectObject(TempDC, CacheBackground);
        if not FCachedBuffer then
          BitBlt(BufferDC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, TempDC, 0, 0, SRCCOPY)
        else
          BitBlt(BufferDC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, TempDC,
            UpdateRect.Left, UpdateRect.Top, SRCCOPY);
        DeleteDC(TempDC);
      end
      else
        DrawParentImage(Self, BufferDC, False);
    end else
      if (not DoubleBuffered) then
        if not IsStyledClientControl(Self) then
          FillRect(BufferDC, ClientRect, Brush.Handle)
        else
        begin
          SetDCBrushColor(BufferDC, ColorToRGB(StyleServices.GetSystemColor(Color)));
          FillRect(BufferDC, ClientRect, GetStockObject(DC_BRUSH));
        end;

  FCanvas.Lock;
  try
    Canvas.Handle := BufferDC;
    TControlCanvas(Canvas).UpdateTextFlags;
    Paint;
    // Canvas.Brush.Color := Random(256*256*256);
    // Canvas.FillRect(Updaterect);
  finally
    FCanvas.Handle := 0;
    FCanvas.Unlock;
  end;

  if BufferedThis then
  begin
  //------------------------------------------------------------------------------------------------
  // Dublicate code, see PaintHandler
  //------------------------------------------------------------------------------------------------
    // draw to window
    if not DoubleBuffered then
    begin
      if not FCachedBuffer then
      begin
        // [restore coord], if need
        SetViewportOrgEx(BufferDC, SaveViewport.X, SaveViewport.Y, nil);
        BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC, 0, 0, SRCCOPY);
      end
      else
      begin
        BitBlt(DC, UpdateRect.Left, UpdateRect.Top, UpdateRect.Width, UpdateRect.Height, BufferDC,
          UpdateRect.Left, UpdateRect.Top, SRCCOPY);
        DeleteObject(Region);
      end;
      DeleteDC(BufferDC);
    end;

    // delete buufer, if need
    if not FCachedBuffer and (BufferBitMap <> 0) then
      DeleteObject(BufferBitMap);
  //------------------------------------------------------------------------------------------------
  end;
end;

function TEsCustomControl.IsBufferedChildrensStored: Boolean;
begin
  Result := not ParentBufferedChildrens;
end;

procedure TEsCustomControl.SetBufferedChildrens(const Value: Boolean);
begin
  if Value <> FBufferedChildrens then
  begin
    FBufferedChildrens := Value;
    FParentBufferedChildrens := False;
    NotifyControls(CM_PARENT_BUFFEREDCHILDRENS_CHANGED);
  end;
end;

procedure TEsCustomControl.SetCachedBackground(Value: Boolean);
begin
  if Value <> FCachedBackground then
  begin
    FCachedBackground := Value;
    if not FCachedBackground then BitMapDeleteAndNil(CacheBackground);
  end;
end;

procedure TEsCustomControl.SetCachedBuffer(Value: Boolean);
begin
  if Value <> FCachedBuffer then
  begin
    FCachedBuffer := Value;
    if not FCachedBuffer then BitMapDeleteAndNil(CacheBitmap);
  end;
end;

procedure TEsCustomControl.SetIsDrawHelper(const Value: Boolean);
begin
  FIsDrawHelper := Value;
  if csDesigning in ComponentState then Invalidate;
end;

procedure TEsCustomControl.SetIsOpaque(const Value: Boolean);
begin
  if (FIsOpaque = True) and (Value = False) then
  begin
    FIsOpaque := Value;
    ControlStyle := ControlStyle - [csOpaque];
    Invalidate;
  end else
  begin
    ControlStyle := ControlStyle + [csOpaque];
    FIsOpaque := Value;
  end;
end;

procedure TEsCustomControl.SetParentBufferedChildrens(const Value: Boolean);
begin
  //FParentBufferedChildrens := Value;
  if Value <> FParentBufferedChildrens then
  begin
//    if (Parent <> nil) and Value then
//    begin
//      if Parent is TESCustomControl then
//        BufferedChildrens := TESCustomControl(Parent).BufferedChildrens
//      else
//        BufferedChildrens := False;
//    end
//    else
//      if Value then
//        BufferedChildrens := False;
//    FParentBufferedChildrens := Value;
    FParentBufferedChildrens := Value;
    if (Parent <> nil) and not (csReading in ComponentState) then
      Perform(CM_PARENT_BUFFEREDCHILDRENS_CHANGED, 0, 0);
  end;
end;

procedure TEsCustomControl.UpdateBackground;
begin
  UpdateBackground(true);
end;

procedure TEsCustomControl.UpdateText;
begin
end;

procedure TEsCustomControl.UpdateBackground(Repaint: Boolean);
begin
  // Delete cache background
  if CacheBackground <> 0 then BitMapDeleteAndNil(CacheBackground);
  if Repaint then Invalidate;
end;

procedure TEsCustomControl.WMEraseBkgnd(var Message: TWMEraseBkgnd);
//var
//  UpdateRect: TRect;
begin
  if DoubleBuffered {and not(csOpaque in ControlStyle)} then
  begin
    //if (Parent <> nil) and Parent.DoubleBuffered then
    //begin
    //  Message.Result := 1;
    //  exit;
    //end;
    //PerformEraseBackground(Self, Message.DC);
    //PaintWindow(Message.DC);
    //GetClipBox(Message.DC, UpdateRect);
    //FillRect(Message.DC, UpdateRect{Rect(0, 0, Width, Height)}, Brush.Handle);
    Inherited;
    Message.Result := 1;
    exit;
  end;
  Message.Result := 1;
end;

procedure TEsCustomControl.WMNCHitTest(var Message: TWMNCHitTest);
begin
  if (not FIsTransparentMouse) and not(csDesigning in ComponentState) then
    Message.Result := HTTRANSPARENT
  else
    inherited;
end;

procedure TEsCustomControl.WMPaint(var Message: TWMPaint);
begin
  ControlState := ControlState + [csCustomPaint];
  if BufferedChildrens and (not FDoubleBuffered or (Message.DC <> 0)) then
  begin
    PaintHandler(Message)// My new PaintHandler
  end
  else
    inherited;// WMPaint(Message);
  ControlState := ControlState - [csCustomPaint];
end;

procedure TEsCustomControl.WMSize(var Message: TWMSize);
begin
  DeleteCache;
  inherited;
end;

procedure TEsCustomControl.WMWindowPosChanged(var Message: TWMWindowPosChanged);
begin
  if not (csOpaque in ControlStyle) and ParentBackground{ and not CachedBackground }then
    Invalidate;
  Inherited;
end;

end.

