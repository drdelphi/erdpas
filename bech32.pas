unit bech32;

interface

uses
  SysUtils;

type TBech32Converter = class
       class function Encode(hrp: string; data: TBytes): string;
       class function Decode(var hrp: string; bech32: string): TBytes;
     end;

implementation

const
  charset : string = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  charset_rev: array[0..127] of ShortInt = (
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    15, -1, 10, 17, 21, 20, 26, 30,  7,  5, -1, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
     1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
     1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1);

function bech32_polymod_step(pre: UInt32): UInt32;
var
  b: Byte;
begin
    b := pre shr 25;
    Result := ((pre and $1FFFFFF) shl 5) xor
        (-((b shr 0) and 1) and $3b6a57b2) xor
        (-((b shr 1) and 1) and $26508e6d) xor
        (-((b shr 2) and 1) and $1ea119fa) xor
        (-((b shr 3) and 1) and $3d4233dd) xor
        (-((b shr 4) and 1) and $2a1462b3);
end;

function convert_bits(data: TBytes; outbits, inbits: byte; pad: boolean): TBytes;
var
  val: UInt32;
  bits: Uint32;
  maxv: UInt32;
  i, len: Integer;
begin
    val := 0;
    bits := 0;
    maxv := (1 shl outbits) - 1;
    len := Length(data);
    i := 0;
    SetLength(Result, 0);
    while len > 0 do
    begin
        val := (val shl inbits) or data[i];
        bits := bits + inbits;
        while bits >= outbits do
        begin
            bits := bits - outbits;
            SetLength(Result, Length(Result) + 1);
            Result[Length(Result) - 1] := (val shr bits) and maxv;
        end;
        inc(i);
        dec(len);
    end;
    if (pad) then
    begin
        if (bits > 0) then
        begin
            SetLength(Result, Length(Result) + 1);
            Result[Length(Result) - 1] := (val shl (outbits - bits)) and maxv;
        end;
    end else
    if (((val shl (outbits - bits)) and maxv) > 0) or (bits >= inbits) then
    begin
      SetLength(Result, 0);
      Exit;
    end;
end;

class function TBech32Converter.Encode(hrp: string; data: TBytes): string;
var
  chk: UInt32;
  i: Uint32;
  ch: Uint32;
  bytes: TBytes;
begin
    bytes := convert_bits(data, 5, 8, true);
    chk := 1;
    i := 1;
    while i <= Length(hrp) do
    begin
        ch := ord(hrp[i]);
        if (ch < 33) or (ch > 126) then
        begin
            Result := '';
            Exit;
        end;
        if (ch >= ord('A')) and (ch <= ord('Z')) then
        begin
            Result := '';
            Exit;
        end;
        chk := bech32_polymod_step(chk) xor (ch shr 5);
        inc(i);
    end;
    if (Length(hrp) + 7 + Length(bytes) > 90) then
    begin
      Result := '';
      Exit;
    end;
    chk := bech32_polymod_step(chk);
    i := 1;
    Result := '';
    while i <= Length(hrp) do
    begin
        chk := bech32_polymod_step(chk) xor (ord(hrp[i]) and $1f);
        Result := Result + hrp[i];
        inc(i);
    end;
    Result := Result + '1';
    for i := 0 to Length(bytes) - 1 do
    begin
        if (bytes[i] shr 5) > 0 then
        begin
          Result := '';
          Exit;
        end;
        chk := bech32_polymod_step(chk) xor bytes[i];
        Result := Result + charset[bytes[i] + 1];
    end;
    for i := 0 to 5 do
        chk := bech32_polymod_step(chk);
    chk := chk xor 1;
    for i := 0 to 5 do
      Result := Result + charset[(chk shr ((5 - i) * 5)) and $1f + 1];
end;

class function TBech32Converter.Decode(var hrp: string; bech32: string): TBytes;
var
  chk: UInt32;
  i: UInt32;
  input_len: UInt32;
  hrp_len: UInt32;
  data_len: UInt32;
  have_lower, have_upper: Integer;
  v: Integer;
  ch: Byte;
begin
    chk := 1;
    input_len := Length(bech32);
    have_lower := 0;
    have_upper := 0;
    SetLength(Result, 0);
    data_len := 0;
    if (input_len < 8) or (input_len > 90) then
        Exit;
    while (data_len < input_len) and (bech32[input_len - data_len] <> '1') do
        inc(data_len);
    hrp_len := input_len - (1 + data_len);
    if (1 + data_len >= input_len) or (data_len < 6) then
    begin
        SetLength(Result, 0);
        Exit;
    end;
    data_len := data_len - 6;
    SetLength(hrp, hrp_len);
    for i := 0 to hrp_len - 1 do
    begin
        ch := ord(bech32[i + 1]);
        if (ch < 33) or (ch > 126) then
        begin
          SetLength(Result, 0);
          Exit;
        end;
        if (ch >= ord('a')) and (ch <= ord('z')) then begin
            have_lower := 1;
        end else
        if (ch >= ord('A')) and (ch <= ord('Z')) then begin
            have_upper := 1;
            ch := (ch - ord('A')) + ord('a');
        end;
        hrp[i + 1] := chr(ch);
        chk := bech32_polymod_step(chk) xor (ch shr 5);
    end;
    chk := bech32_polymod_step(chk);
    for i := 0 to hrp_len - 1 do
        chk := bech32_polymod_step(chk) xor (ord(bech32[i + 1]) and $1f);
    i := hrp_len + 1;
    while i < input_len do
    begin
        v := charset_rev[ord(bech32[i + 1])];
        if (bech32[i + 1] >= 'a') and (bech32[i + 1] <= 'z') then
          have_lower := 1;
        if (bech32[i + 1] >= 'A') and (bech32[i + 1] <= 'Z') then
          have_upper := 1;
        if v = -1 then
        begin
            SetLength(Result, 0);
            Exit;
        end;
        chk := bech32_polymod_step(chk) xor v;
        if i + 6 < input_len then
        begin
            SetLength(Result, i - hrp_len);
            Result[i - (1 + hrp_len)] := v;
        end;
        inc(i);
    end;
    if ((have_lower > 0) and (have_upper > 0)) or (chk <> 1) then
        SetLength(Result, 0);
    Result := convert_bits(Result, 8, 5, false);
end;

end.
