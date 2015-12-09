unit diocp_ex_httpClient;

interface

uses
  Classes
  {$IFDEF POSIX}
  , diocp.core.rawPosixSocket
  {$ELSE}
  , diocp.core.rawWinSocket
  , diocp.winapi.winsock2
  , SysConst
  {$ENDIF}
  , SysUtils, utils_URL, utils.strings;




const
  HTTP_HEADER_END :array[0..3] of Byte=(13,10,13,10);

type
  //2007����ֱ��=TBytes
{$if CompilerVersion< 18.5}
  TBytes = array of Byte;
{$IFEND}

  TDiocpHttpClient = class(TComponent)
  private
    FURL: TURL;
    FRawSocket: TRawSocket;
    FRequestAccept: String;
    FRequestAcceptEncoding: String;
    FRawCookie:String;

    FRequestBody: TMemoryStream;
    FRequestContentType: String;
    FRequestHeader: TStringList;
    FResponseBody: TMemoryStream;
    FResponseContentType: String;
    FResponseHeader: TStringList;
    /// <summary>
    ///  CheckRecv buffer
    /// </summary>
    procedure CheckRecv(buf: Pointer; len: cardinal);
    procedure CheckSocketResult(pvSocketResult:Integer);
    procedure InnerExecuteRecvResponse();
    procedure Close;
  public
    procedure Cleaup;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Post(pvURL:String);
    procedure Get(pvURL:String);
    /// <summary>
    ///   �������:
    ///    �������ݵı�������
    ///    Accept-Encoding:gzip,deflate
    /// </summary>
    property RequestAcceptEncoding: String read FRequestAcceptEncoding write
        FRequestAcceptEncoding;

    /// <summary>
    ///   �������:
    ///    ������������
    ///    Accept:text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8
    /// </summary>
    property RequestAccept: String read FRequestAccept write FRequestAccept;
        
    /// <summary>
    ///  POST����ʱ, ������������
    /// </summary>
    property RequestContentType: String read FRequestContentType write
        FRequestContentType;

    property RequestBody: TMemoryStream read FRequestBody;
    property RequestHeader: TStringList read FRequestHeader;

    property ResponseBody: TMemoryStream read FResponseBody;
    property ResponseHeader: TStringList read FResponseHeader;
    
    /// <summary>
    ///   ��Ӧ�õ���ͷ��Ϣ
    ///   ���ص���������
    ///     Content-Type:image/png
    ///     Content-Type:text/html; charset=utf-8
    /// </summary>
    property ResponseContentType: String read FResponseContentType;

  end;


procedure WriteStringToStream(pvStream: TStream; pvDataString: string;
    pvConvert2Utf8: Boolean = true);

function ReadStringFromStream(pvStream: TStream; pvIsUtf8Raw:Boolean): String;


implementation

{ TDiocpHttpClient }

{$IFDEF POSIX}

{$ELSE}
// <2007�汾��Windowsƽ̨ʹ��
//   SOSError = 'System Error.  Code: %d.'+sLineBreak+'%s';
procedure RaiseLastOSErrorException(LastError: Integer);
var       // �߰汾�� SOSError��3������
  Error: EOSError;
begin
  if LastError <> 0 then
    Error := EOSError.CreateResFmt(@SOSError, [LastError,
      SysErrorMessage(LastError)])
  else
    Error := EOSError.CreateRes(@SUnkOSError);
  Error.ErrorCode := LastError;
  raise Error;
end;

{$ENDIF}

procedure WriteStringToStream(pvStream: TStream; pvDataString: string;
    pvConvert2Utf8: Boolean = true);
{$IFDEF UNICODE}
var
  lvRawData:TBytes;
{$ELSE}
var
  lvRawStr:AnsiString;
{$ENDIF}
begin
{$IFDEF UNICODE}
  if pvConvert2Utf8 then
  begin
    lvRawData := TEncoding.UTF8.GetBytes(pvDataString);
  end else
  begin
    lvRawData := TEncoding.Default.GetBytes(pvDataString);
  end;
  pvStream.Write(lvRawData[0], Length(lvRawData));
{$ELSE}
  if pvConvert2Utf8 then
  begin
    lvRawStr := UTF8Encode(pvDataString);
  end else
  begin
    lvRawStr := AnsiString(pvDataString);
  end;
  pvStream.WriteBuffer(PAnsiChar(lvRawStr)^, length(lvRawStr));
{$ENDIF}
end;

function ReadStringFromStream(pvStream: TStream; pvIsUtf8Raw:Boolean): String;
{$IFDEF UNICODE}
var
  lvRawData:TBytes;
{$ELSE}
var
  lvRawStr:AnsiString;
{$ENDIF}
begin
{$IFDEF UNICODE}
  SetLength(lvRawData, pvStream.Size);
  pvStream.Position := 0;
  pvStream.Read(lvRawData[0], pvStream.Size);

  if pvIsUtf8Raw then
  begin
    Result := TEncoding.UTF8.GetString(lvRawData);
  end else
  begin
    Result := TEncoding.Default.GetString(lvRawData);
  end;
{$ELSE}
  SetLength(lvRawStr, pvStream.Size);
  pvStream.Position := 0;
  pvStream.Read(PAnsiChar(lvRawStr)^, pvStream.Size);
  if pvIsUtf8Raw then
  begin
    Result := UTF8Decode(lvRawStr);
  end else
  begin
    Result := AnsiString(lvRawStr);
  end;
{$ENDIF}
end;

constructor TDiocpHttpClient.Create(AOwner: TComponent);
begin
  inherited;
  FRawSocket := TRawSocket.Create;
  FRequestBody := TMemoryStream.Create;
  FRequestHeader := TStringList.Create;

  FResponseBody := TMemoryStream.Create;
  FResponseHeader := TStringList.Create;

  FURL := TURL.Create;

{$if CompilerVersion >= 18.5}
  FRequestHeader.LineBreak := #13#10;
  FResponseHeader.LineBreak := #13#10;
{$IFEND}

end;

destructor TDiocpHttpClient.Destroy;
begin
  FRawSocket.Free;
  FResponseHeader.Free;
  FResponseBody.Free;
  FRequestHeader.Free;
  FRequestBody.Free;
  FURL.Free;
  inherited;
end;

procedure TDiocpHttpClient.CheckSocketResult(pvSocketResult: Integer);
var
  lvErrorCode:Integer;
begin
  {$IFDEF POSIX}
  if (pvSocketResult = -1) or (pvSocketResult = 0) then
  begin
     try
       RaiseLastOSError;
     except
       FRawSocket.Close;
       raise;
     end;
   end;
  {$ELSE}
  if (pvSocketResult = SOCKET_ERROR) then
  begin
    lvErrorCode := GetLastError;
    FRawSocket.Close;     // �����쳣��Ͽ�����

    {$if CompilerVersion < 23}
    RaiseLastOSErrorException(lvErrorCode);
    {$ELSE}
    RaiseLastOSError(lvErrorCode);
    {$ifend} 
  end;
  {$ENDIF}
end;

procedure TDiocpHttpClient.Cleaup;
begin
  FRequestBody.Clear;
  FResponseBody.Clear;
end;

procedure TDiocpHttpClient.Close;
begin
  FRawSocket.Close();
end;

procedure TDiocpHttpClient.Get(pvURL: String);
var
  r, len:Integer;
  lvIpAddr:string;
{$IFDEF UNICODE}
  lvRawHeader:TBytes;
{$ELSE}
  lvRawHeader:AnsiString;
{$ENDIF}
begin
  FURL.SetURL(pvURL);
  FRequestHeader.Clear;
  if FURL.ParamStr = '' then
  begin
    FRequestHeader.Add(Format('GET %s HTTP/1.1', [FURL.URI]));
  end else
  begin
    FRequestHeader.Add(Format('GET %s HTTP/1.1', [FURL.URI + '?' + FURL.ParamStr]));
  end;
  FRequestHeader.Add(Format('Host: %s', [FURL.RawHostStr]));
  
  if FRawCookie <> '' then
  begin
    FRequestHeader.Add('Cookie:' + FRawCookie);
  end;
  
  FRequestHeader.Add('');                 // ����һ���س���

  FRawSocket.CreateTcpSocket;

  // ������������
  lvIpAddr := FRawSocket.GetIpAddrByName(FURL.Host);

  if not FRawSocket.Connect(lvIpAddr,StrToIntDef(FURL.Port, 80)) then
  begin
    RaiseLastOSError;
  end;

{$IFDEF UNICODE}
  lvRawHeader := TEncoding.Default.GetBytes(FRequestHeader.Text);
  len := Length(lvRawHeader);
  r := FRawSocket.SendBuf(PByte(lvRawHeader)^, len);
  CheckSocketResult(r);
  if r <> len then
  begin
    raise Exception.Create(Format('ָ�����͵����ݳ���:%d, ʵ�ʷ��ͳ���:%d', [len, r]));
  end;
{$ELSE}
  lvRawHeader := FRequestHeader.Text;
  len := Length(lvRawHeader);
  r := FRawSocket.SendBuf(PAnsiChar(lvRawHeader)^, len);
  CheckSocketResult(r);
  if r <> len then
  begin
    raise Exception.Create(Format('ָ�����͵����ݳ���:%d, ʵ�ʷ��ͳ���:%d', [len, r]));
  end;
{$ENDIF}

  InnerExecuteRecvResponse();
end;

procedure TDiocpHttpClient.InnerExecuteRecvResponse;
var
  lvRawHeader, lvBytes:TBytes;
  r, l:Integer;
  lvTempStr, lvRawHeaderStr:String;

begin
  // ����2048����ĳ��ȣ���Ϊ�Ǵ����
  SetLength(lvRawHeader, 2048);
  FillChar(lvRawHeader[0], 2048, 0);
  //FRawSocket.SetReadTimeOut(3000);
  r := FRawSocket.RecvBufEnd(@lvRawHeader[0], 2048, @HTTP_HEADER_END[0], 4);
  if r = 0 then
  begin
    // �Է����ر�
    Close;
  end;
  // ����Ƿ��д���
  CheckSocketResult(r);
  
  {$IFDEF UNICODE}
  lvRawHeaderStr := TEncoding.Default.GetString(lvRawHeader);
  {$ELSE}
  lvRawHeaderStr := StrPas(@lvRawHeader[0]);
  {$ENDIF}

  FResponseHeader.Text := lvRawHeaderStr;
  FResponseContentType := StringsValueOfName(FResponseHeader, 'Content-Type', [':'], True);
  lvTempStr := StringsValueOfName(FResponseHeader, 'Content-Length', [':'], True);
  l := StrToIntDef(lvTempStr, 0);
  if l > 0 then
  begin
    FResponseBody.SetSize(l);
    CheckRecv(FResponseBody.Memory, l);    
  end;

  lvTempStr := StringsValueOfName(FResponseHeader, 'Set-Cookie', [':'], True);

  if lvTempStr <> '' then
  begin  
    FRawCookie := lvTempStr;
  end;


  

  
  
  

end;

procedure TDiocpHttpClient.Post(pvURL: String);
var
  r, len:Integer;
  lvIpAddr:string;
{$IFDEF UNICODE}
  lvRawHeader:TBytes;
{$ELSE}
  lvRawHeader:AnsiString;
{$ENDIF}
begin
  FURL.SetURL(pvURL);
  FRequestHeader.Clear;
  if FURL.ParamStr = '' then
  begin
    FRequestHeader.Add(Format('POST %s HTTP/1.1', [FURL.URI]));
  end else
  begin
    FRequestHeader.Add(Format('POST %s HTTP/1.1', [FURL.URI + '?' + FURL.ParamStr]));
  end;

  if FRawCookie <> '' then
  begin
    FRequestHeader.Add('Cookie:' + FRawCookie);
  end;

  FRequestHeader.Add(Format('Host: %s', [FURL.RawHostStr]));
  FRequestHeader.Add(Format('Content-Length: %d', [self.FRequestBody.Size]));
  if FRequestContentType = '' then
  begin
    FRequestContentType := 'application/x-www-form-urlencoded';
  end;
  FRequestHeader.Add(Format('Content-Type: %s', [FRequestContentType]));

  FRequestHeader.Add('');                 // ����һ���س���

  FRawSocket.CreateTcpSocket;

  // ������������
  lvIpAddr := FRawSocket.GetIpAddrByName(FURL.Host);
  
  if not FRawSocket.Connect(lvIpAddr,StrToIntDef(FURL.Port, 80)) then
  begin
    RaiseLastOSError;
  end;

{$IFDEF UNICODE}
  lvRawHeader := TEncoding.Default.GetBytes(FRequestHeader.Text);
  len := Length(lvRawHeader);
  r := FRawSocket.SendBuf(PByte(lvRawHeader)^, len);
  CheckSocketResult(r);
  if r <> len then
  begin
    raise Exception.Create(Format('ָ�����͵����ݳ���:%d, ʵ�ʷ��ͳ���:%d', [len, r]));
  end;
{$ELSE}
  lvRawHeader := FRequestHeader.Text;
  len := Length(lvRawHeader);
  r := FRawSocket.SendBuf(PAnsiChar(lvRawHeader)^, len);
  CheckSocketResult(r);
  if r <> len then
  begin
    raise Exception.Create(Format('ָ�����͵����ݳ���:%d, ʵ�ʷ��ͳ���:%d', [len, r]));
  end;
{$ENDIF}

  // ��������������
  if FRequestBody.Size > 0 then
  begin
    len := FRequestBody.Size;
    r := FRawSocket.SendBuf(FRequestBody.Memory^, len);
    CheckSocketResult(r);
    if r <> len then
    begin
      raise Exception.Create(Format('ָ�����͵����ݳ���:%d, ʵ�ʷ��ͳ���:%d', [len, r]));
    end;
  end;

  InnerExecuteRecvResponse();
end;

procedure TDiocpHttpClient.CheckRecv(buf: Pointer; len: cardinal);
var
  lvTempL :Integer;
  lvReadL :Cardinal;
  lvPBuf:Pointer;
begin
  lvReadL := 0;
  lvPBuf := buf;
  while lvReadL < len do
  begin
    lvTempL := FRawSocket.RecvBuf(lvPBuf^, len - lvReadL);

    CheckSocketResult(lvTempL);

    lvPBuf := Pointer(IntPtr(lvPBuf) + Cardinal(lvTempL));
    lvReadL := lvReadL + Cardinal(lvTempL);
  end;
end;

end.