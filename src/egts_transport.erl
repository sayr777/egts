%%%-------------------------------------------------------------------
%%% @author shepver
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Дек. 2014 15:14
%%%-------------------------------------------------------------------
-module(egts_transport).

-author("shepver").

-include("../include/egts_types.hrl").
-include("../include/egts_code.hrl").
-include("../include/egts_record.hrl").
%% API
-export([parse/1, pack/1, response/1]).


%%  Заголовок протокола Транспортного уровня состоит из следующих полей
%% PRV-(8), -  содержит значение 0x01. Значение данного параметра инкрементируется каждый раз при внесении изменений в структуру заголовка.

%% SKID-(8), - (Security Key ID) определяет идентификатор ключа, используемого при шифровании.

%% PRF-(2), - определяет префикс заголовка Транспортного уровня и содержит значение 00.

%% RTE -(1), - (Route) определяет необходимость дальнейшей маршрутизации данного пакета на
%% удаленный аппаратно-программный комплекс, а также наличие опциональных параметров PRA, RCA,
%% TTL, необходимых для маршрутизации данного пакета. Если поле имеет значение 1, то необходима
%% маршрутизация и поля PRA, RCA, TTL присутствуют в пакете. Данное поле устанавливает Диспетчер
%% того аппаратно-программного комплекса, на котором сгенерирован пакет, или абонентский терминал,
%% сгенерировавший пакет для отправки на аппаратно-программный комплекс, в случае установки в нем
%% параметра "HOME_DISPATCHER_ID", определяющего адрес аппаратно-программного комплекса, на
%% котором данный абонентский терминал зарегистрирован.

%% ENA-(2), - (Encryption Algorithm) определяет код алгоритма, используемый для шифрования
%% данных из поля SFRD. Если поле имеет значение 00, то данные в поле SFRD не шифруются.

%% CMP -(1), - (Compressed) определяет, используется ли сжатие данных из поля SFRD. Если
%% поле имеет значение 1, то данные в поле SFRD считаются сжатыми.

%% PR -(2), -  (Priority) определяет приоритет маршрутизации данного пакета и может принимать
%% следующие значения:
%% 00 - наивысший
%% 01 - высокий
%% 10 - средний
%% 11 - низкий

%% HL-(8), -- длина заголовка Транспортного уровня в байтах с учетом байта контрольной суммы
%% (поля HCS)

%% HE-(8), -  определяет применяемый метод кодирования следующей за данным параметром
%% части заголовка Транспортного уровня.

%% FDL-(16), -  определяет размер в байтах поля данных SFRD, содержащего информацию
%% протокола Уровня поддержки услуг.

%% PID -(16), -  содержит номер пакета Транспортного уровня, увеличивающийся на 1 при отправке
%% каждого нового пакета на стороне отправителя. Значения в данном поле изменяются по правилам
%% циклического счетчика в диапазоне от 0 до 65535, т.е. при достижении значения 65535 следующее
%% значение 0.

%% PT -(8), -  тип пакета Транспортного уровня. Поле PT может принимать следующие значения.
%% 0 - EGTS_PT_RESPONSE (подтверждение на пакет Транспортного уровня);
%% 1 - EGTS_PT_APPDATA (пакет, содержащий данные протокола Уровня поддержки услуг);
%% 2 - EGTS_PT_SIGNED_APPDATA (пакет, содержащий данные протокола Уровня поддержки услуг с
%% цифровой подписью).

%% PRA-(16), - адрес аппаратно-программного комплекса, на котором данный пакет сгенерирован.
%% Данный адрес является уникальным в рамках сети и используется для создания пакета-подтверждения
%% на принимающей стороне.

%% RCA-(16), - адрес аппаратно-программного комплекса, для которого данный пакет
%% предназначен. По данному адресу производится идентификация принадлежности пакета определенного
%% аппаратно-программного комплекса и его маршрутизация при использовании промежуточных
%% аппаратно-программных комплексов.

%% TTL-(8), - время жизни пакета при его маршрутизации между аппаратно-программными
%% комплексами. Использование данного параметра предотвращает зацикливание пакета при ретрансляции
%% в системах со сложной топологией адресных пунктов.

%% HCS-(8), -  контрольная сумма заголовка Транспортного уровня (начиная с поля "PRV" до
%% поля "HCS", не включая поле "HCS"). Для подсчета значения поля HCS ко всем байтам указанной
%% последовательности применяется алгоритм CRC-8.

%%
%% SFRD,
%% SFRCS

%% encode(
%%     PRV,
%%     SKID,
%%     PRF, RTE, ENA, CMP, PR,
%%     HL,
%%     HE,
%%     FDL,
%%     PID,
%%     PT,
%%     PRA,
%%     RCA,
%%     TTL,
%%     HCS,
%%     SFRD,
%%     SFRCS) -> ok.
%%
%% decode() -> ok.


parse(<<PVR:?BYTE, _:?BYTE, PRF:2, _/binary>> = _Data) when (PVR =/= 1) and (PRF =/= 2#00) ->
  {error, ?EGTS_PC_UNS_PROTOCOL};
parse(<<_:24, HL:?BYTE, _/binary>> = _Data) when (HL =/= 11) andalso (HL =/= 16) ->
  error_logger:info_msg(" HL = ~p ", [HL]),
  {error, ?EGTS_PC_INC_HEADERFORM};
parse(<<_:40, FDL:?USHORT, _/binary>> = _Data) when (FDL =:= 0) ->
  {error, ?EGTS_PC_OK};
parse(<<1:?BYTE, _Skid:?BYTE, 0:2, 0:1, 0:2, 0:1, _PR:2, 11:?BYTE, _:8, FDL:?USHORT, PID:?USHORT, PT:?BYTE, _/binary>> = Data) when (FDL > 0) ->
  <<Header:10/binary-unit:8, HCS:?BYTE, FD/binary>> = Data,
%%   error_logger:error_msg("FDL ~p FD size ~p FD ~p ",[FDL,byte_size(FD),FD]),
  case FD of
    <<SFRD:FDL/binary-unit:8, SFRCS:?USHORT>> -> [spack(PT, PID, HCS, Header, SFRCS, SFRD)];
    <<SFRD:FDL/binary-unit:8, SFRCS:?USHORT, Tail/binary>> -> [spack(PT, PID, HCS, Header, SFRCS, SFRD) | parse(Tail)]
  end;
parse(_Data) ->
  {error, unknown}.

spack(PT, PID, HCS, Header, SFRCS, SFRD) ->
  case {egts_utils:check_crc8(HCS, Header), egts_utils:check_crc16(SFRCS, SFRD)} of
    {true, true} -> {ok, {PT, PID, SFRD}};
    {false, _} -> {error, ?EGTS_PC_HEADERCRC_ERROR};
    {_, false} -> {error, ?EGTS_PC_DATACRC_ERROR}
  end
.


response({Data, OID}) ->
%%   case parse(Data) of
%%     {ok, {?EGTS_PT_RESPONSE, _PID, SFRD}} ->
%%       <<RPID:?USHORT, PR:?BYTE, Other/binary>> = SFRD,
%%       {ok, #egts_pt_response{rpid = RPID, pr = PR, record_list = Other}};
%%     {ok, {?EGTS_PT_APPDATA, PID, SFRD}} ->
%%       {ok, RData} = egts_service:pars_for_responce({SFRD, OID}),
%%       {ok, #egts_pt_appdata{record_list = SFRD, response = <<PID:?USHORT, ?EGTS_PC_OK:?BYTE, RData/binary>>}};
%%     All -> All
%%   end
  rlpars(OID, parse(Data))
.

rlpars(_, []) -> [];
rlpars(OID, [{ok, {?EGTS_PT_RESPONSE, _PID, SFRD}} | T]) ->
  <<RPID:?USHORT, PR:?BYTE, Other/binary>> = SFRD,
  [{ok, #egts_pt_response{rpid = RPID, pr = PR, record_list = Other}} | rlpars(OID, T)];
rlpars(OID, [{ok, {?EGTS_PT_APPDATA, PID, SFRD}} | T]) ->
  {ok, RData} = egts_service:pars_for_responce({SFRD, OID}),
  [{ok, #egts_pt_appdata{record_list = SFRD, response = <<PID:?USHORT, ?EGTS_PC_OK:?BYTE, RData/binary>>}} | rlpars(OID, T)];
rlpars(OID, [ERROR | T]) ->
  [ERROR | rlpars(OID, T)].


pack([Data, Pid]) ->
  pack([Data, Pid, ?EGTS_PT_APPDATA]);
pack([Data, Pid, PType]) ->
  FDL = byte_size(Data),
  Flag = <<0:2, 0:1, 0:2, 0:1, 1:2>>,
  Header =
    <<1:?BYTE,
    2#00:?BYTE,
    Flag/binary,
    11:?BYTE,
    0:?BYTE,
    FDL:?USHORT,
    Pid:?USHORT,
    PType:?BYTE>>,
  HCS = egts_utils:crc8(Header),
  SFRCS = egts_utils:crc16(Data),
  {ok, <<Header/binary, HCS:?BYTE, Data/binary, SFRCS:?USHORT>>}
.