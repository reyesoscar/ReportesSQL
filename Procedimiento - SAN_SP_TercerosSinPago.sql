-- exec SAN_SP_TercerosSinPago '202415',''

ALTER PROCEDURE [dbo].[SAN_SP_TercerosSinPago] (
@Qna_Proc nvarchar(6), @sMensaje varchar(max) OUTPUT)
AS
BEGIN
declare @vi date;


BEGIN TRY

-- obtener VI de la quincena a revisar

select @vi = VigenciaInicial from HW_RH_PeriodoNomina WHERE concat(Ano,FORMAT(NumeroPeriodo,'00')) = @Qna_Proc;


if OBJECT_ID('#terceros') is not null 
begin
	drop table #terceros;
end
if OBJECT_ID('#empleadosPago') is not null 
begin
	drop table #empleadosPago;
end
if OBJECT_ID('#tercerosSinPagos') is not null 
begin
	drop table #tercerosSinPagos;
end
if OBJECT_ID('#tercerosPagos') is not null 
begin
	drop table #tercerosPagos;
end
if OBJECT_ID('#deducciones') is not null 
begin
	drop table #deducciones;
end
if OBJECT_ID('#VigenciasOcupaciones') is not null 
begin
	drop table #VigenciasOcupaciones;
end
if OBJECT_ID('#estadosOc') is not null 
begin
	drop table #estadosOc;
end
if OBJECT_ID('#estadosOc2') is not null 
begin
	drop table #estadosOc2;
end
if OBJECT_ID('#estadosOc3') is not null 
begin
	drop table #estadosOc3;
end
if OBJECT_ID('sn_rpt_tercerosSinPago') is not null 
begin
	drop table sn_rpt_tercerosSinPago;
end
if OBJECT_ID('#ocbajas') is not null 
begin
	drop table #ocbajas;
end
if OBJECT_ID('#trbajas') is not null 
begin
	drop table #trbajas;
end



select 
	e.NumEmpleado,e.rfc,
	CONCAT(e.Nombre,' ',e.Apellido1,' ',e.Apellido2) AS Nombre,
	c.NumeroConcepto, c.ClaveAntecedente, 
	t.Importe,
	t.Porcentaje,
	t.VigenciaInicial, t.VigenciaFinal 
	into #terceros
from 
HW_RH_Terceros t
join HW_AH_Empleado e on t.NumEmpleado = e.NumEmpleado
join HW_RH_Concepto c on c.Id_Concepto = t.Id_Concepto
where ISNULL(T.VigenciaFinal,'9999-12-31') > @vi;


-- identificar a todas las personas que tuvieron pago
select 
	distinct numempleado into #empleadosPago 
from
	hist_percepciones -- hist_percepciones_vigente
where 
	qna_proc = @Qna_Proc and 
	cons_qna_proc = 0;

-- 1er escenario -  identificar a que personas no se les pago en la quincena y que aparecen en la tabla de terceros

select * into #tercerosSinPagos from #terceros where numempleado not in (select numempleado from #empleadosPago);

ALTER TABLE #tercerosSinPagos ADD Estatus varchar(max);
ALTER TABLE #tercerosSinPagos ADD FechaOperacion date;
ALTER TABLE #tercerosSinPagos ADD Tramite varchar(max);


-- Los empleados que no tengan una ocupación activa al inicio de la vigencia de la quincena se consideran como baja definitiva 


SELECT 
	DISTINCT oc.id_ocupacion, oc.numempleado into #ocupaciones
FROM 
	HW_RH_Ocupacion oc
JOIN #tercerosSinPagos e ON oc.numempleado = e.NumEmpleado
JOIN HW_RH_Plaza p on p.NumPlaza = oc.numplaza 
JOIN HW_RH_Categoria c on c.Id_Categoria = SUBSTRING(p.NumPlazaAntecedente,7,7) collate database_default
WHERE 
	@vi BETWEEN oc.VigenciaInicial AND ISNULL(oc.VigenciaFinal,'9999-12-31')
	 AND (c.Id_Categoria not like '%HON%' AND c.Id_Categoria not like '%EVE%' AND c.Id_Categoria not like '%JE%');

	
UPDATE #tercerosSinPagos SET Estatus = 'Baja' WHERE NumEmpleado NOT IN (SELECT NumEmpleado FROM #ocupaciones);

-- identificar el estatus de estos empleados para justificar el que no tuvieran pago

SELECT oc.id_ocupacion, MAX(oc.VigenciaInicial) VI into #VigenciasOcupaciones
FROM HW_RH_HistoriaOcupacion oc
JOIN #ocupaciones oc2 on oc2.id_ocupacion = oc.id_ocupacion and oc.Historia = 0
AND @vi BETWEEN oc.VigenciaInicial AND ISNULL(oc.VigenciaFinal,'9999-12-31')
GROUP BY oc.id_ocupacion;



SELECT distinct oc2.numempleado, oc.id_estadoOcupacion, oc.id_ret INTO #estadosOc
FROM HW_RH_HistoriaOcupacion oc 
JOIN #VigenciasOcupaciones voc ON voc.id_ocupacion = oc.id_ocupacion AND voc.VI = oc.VigenciaInicial
JOIN #ocupaciones oc2 on oc2.id_ocupacion = oc.id_ocupacion
WHERE oc.VigenciaInicial <> ISNULL(oc.VigenciaFinal,'9999-12-31')
AND oc.Historia = 0;

select oc.*, t.Nombre as NombreTramite, te.Fecha_operacion into #estadosOc2
from #estadosOc oc
JOIN HW_VU_TramitesEmpleados te on te.id_ret = oc.id_ret
JOIN HW_RH_Tramite t on t.id_tramite = te.id_tramite;




UPDATE #tercerosSinPagos SET #tercerosSinPagos.Estatus = oc.id_estadoOcupacion, #tercerosSinPagos.FechaOperacion = oc.Fecha_operacion,
#tercerosSinPagos.Tramite = oc.NombreTramite
FROM #tercerosSinPagos
JOIN #estadosOc2 oc ON oc.numempleado = #tercerosSinPagos.NumEmpleado
WHERE 
#tercerosSinPagos.NumEmpleado IN (
	SELECT NumEmpleado FROM #estadosOc
) AND #tercerosSinPagos.Estatus IS NULL;





-- identificar motivo de baja de los empleados inactivos 14/08/2024

select oc.NumEmpleado, -- max(oc.VigenciaInicial) VigenciaInicial 
max(oc.VigenciaFinal) VigenciaFinal 
into #ocbajas
from HW_RH_Ocupacion oc
JOIN #tercerosSinPagos t on oc.NumEmpleado = t.numempleado
WHERE t.Estatus = 'Baja'
group by oc.NumEmpleado;


select distinct oc.NumEmpleado, hoc.Id_Ret into #trbajas
from HW_RH_Ocupacion oc 
join HW_RH_HistoriaOcupacion hoc on oc.Id_Ocupacion = hoc.Id_Ocupacion
where hoc.Id_Ocupacion in (
	select Id_Ocupacion 
	from
	HW_RH_Ocupacion oc 
	join #ocbajas ocb on oc.NumEmpleado = ocb.NumEmpleado and oc.VigenciaFinal = ocb.VigenciaFinal-- oc.VigenciaInicial = ocb.VigenciaInicial
)
and
hoc.Id_EstadoOcupacion = 'BD' and hoc.Historia = 0


create index idx1 on #trbajas(id_ret);


select oc.*, t.Nombre as NombreTramite, te.Fecha_operacion into #estadosOc3
from #trbajas oc
JOIN HW_VU_TramitesEmpleados te on te.id_ret = oc.id_ret AND te.estatus_tramite in ('CONCLUIDO','ENTREGADO')
JOIN HW_RH_Tramite t on t.id_tramite = te.id_tramite;



UPDATE #tercerosSinPagos SET  #tercerosSinPagos.FechaOperacion = oc.Fecha_operacion,
#tercerosSinPagos.Tramite = oc.NombreTramite
FROM #tercerosSinPagos
JOIN #estadosOc3 oc ON oc.numempleado = #tercerosSinPagos.NumEmpleado
WHERE 
#tercerosSinPagos.Estatus = 'Baja';



-- select 'todo bien';


select 
	numempleado, 
	rfc,
	Nombre,
	NumeroConcepto,
	ClaveAntecedente, 
	Importe,
	Porcentaje,
	VigenciaInicial,
	VigenciaFinal,
	CASE 
		WHEN Estatus IN ('LS','PR') THEN 'Licencia'
		WHEN Estatus IN ('SP') THEN 'Suspensión de pago'
		ELSE Estatus 
	END AS Estatus,
	FechaOperacion,
	Tramite
INTO sn_rpt_tercerosSinPago
from #tercerosSinPagos order by rfc;

UPDATE sn_rpt_tercerosSinPago SET Tramite = 'No cuenta con un periodo activo' WHERE Estatus = 'Baja' AND Tramite IS NULL;

-- 2nd escenario - identificar de los terceros personas con pagos, pero que no se les haya cobrado todos los conceptos de terceros en la quincena


select * into #tercerosPagos from #terceros where numempleado in (select numempleado from #empleadosPago);

-- obtener las deducciones de los empleados de terceros 

select * into #deducciones from hist_deducciones where numempleado in (select numempleado from #tercerosPagos) and qna_proc = @Qna_Proc;

-- Obtener a los que no se les pagaron todos los conceptos 

INSERT INTO sn_rpt_tercerosSinPago
select 
	numempleado, 
	rfc,
	Nombre,
	NumeroConcepto,
	ClaveAntecedente, 
	Importe,
	Porcentaje,
	VigenciaInicial,
	VigenciaFinal,
	'Insuficiencia de pago' as Estatus,
	NULL FechaOperacion,
	NULL Tramite
from #tercerosPagos where not exists (
	
	select '' 
	from 
		#deducciones 
	where 
		#tercerosPagos.NumEmpleado = #deducciones.NumEmpleado and 
		#tercerosPagos.NumeroConcepto = #deducciones.NumeroConcepto collate database_default
);

    SET @sMensaje = 'OK';
	   
END TRY
	BEGIN CATCH

	
select 'todo mal';

	insert into SAN_Val_ErroValidacion
		SELECT
		ERROR_PROCEDURE() AS ErrorProcedure,
		ERROR_LINE() AS ErrorLine,
		ERROR_MESSAGE() AS ErrorMessage,
		GETDATE() AS ErrorFecha
	END CATCH;
end
GO