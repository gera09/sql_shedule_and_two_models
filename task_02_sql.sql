# Задание 1
-- -------------------------------------------------------------------------------------------------------------------------------

CREATE DATABASE magnet;
USE magnet;

/*
 * ФИО будет часто повторяться. Чтобы на этом сэкономить и иметь возможность управлять, 
 * разобьем таблицу и создадим подтталицы T_CONTRACTOR_FIO и T_CONTRACTOR_DATA
 *
 **/

-- Таблица FIO
DROP TABLE IF EXISTS T_CONTRACTOR_FIO;
CREATE TABLE T_CONTRACTOR_FIO (
	ID SERIAL PRIMARY KEY,
	NAME VARCHAR(500) COMMENT 'имя поставщика',
	CONSTRAINT UC_NAME UNIQUE (NAME)
	-- если работать не в рамках этой задачи, то следовало бы поместить каждое слово из ФИО в отдельную колонку
);

-- Таблица c данными по расписанию
DROP TABLE IF EXISTS T_CONTRACTOR_DATA;
CREATE TABLE T_CONTRACTOR_DATA (
	ID SERIAL PRIMARY KEY,
	NAME_ID BIGINT UNSIGNED NOT NULL COMMENT 'ID поставщика',
	SHEDULE VARCHAR(500) NULL COMMENT 'расписание',
	DATE_BEGIN DATETIME COMMENT 'дата начала действия расписания',
	DATE_END DATETIME COMMENT 'дата окончания действия расписания',
	CONSTRAINT UC_NAME_ID_DATE_BEGIN UNIQUE (NAME_ID, DATE_BEGIN), 					-- Связку полей FIO, DATE_BEGIN считать уникальной
	CONSTRAINT CH_DATE_END_LATER_THAN_DATE_BEGIN CHECK ((DATE_BEGIN <= DATE_END)),  -- DATE_BEGIN не может привышать DATE_END
	FOREIGN KEY (NAME_ID) REFERENCES T_CONTRACTOR_FIO(ID), 							-- Можете продемонстрировать работу с ключами/ограничениями
	INDEX IND_NAME_ID (NAME_ID)
);

-- Заполнение таблицы рализовал в ноутбуке python

INSERT IGNORE INTO `T_CONTRACTOR_DATA` (NAME_ID,SHEDULE,DATE_BEGIN,DATE_END) VALUES 
	(1,'ДДДВСВНН','2019-01-01 00:00:00','2019-01-10 00:00:00'),
	(1,'ННВННВ','2019-01-11 00:00:00','2019-01-15 00:00:00'),
	(1,'СВ','2019-01-16 00:00:00','2019-01-20 00:00:00'),
	(2,'СВСВСВ','2019-01-01 00:00:00','2019-01-07 00:00:00'),
	(2,'ДНВСВ','2019-01-08 00:00:00','2019-01-14 00:00:00'),
	(2,'ННДДВСВ','2019-01-15 00:00:00','9999-12-31 00:00:00'),
	(3,'НВНВНВ','2019-01-01 00:00:00','2019-02-01 00:00:00'),
	(3,'ДВДВДВДВ','2019-02-02 00:00:00','9999-12-31 00:00:00');


# Задание 2
-- -------------------------------------------------------------------------------------------------------------------------------

-- Таблица c данными по расписанию
DROP TABLE IF EXISTS T_CONTRACTOR_WORK_DAY;
CREATE TABLE T_CONTRACTOR_WORK_DAY (
	ID SERIAL PRIMARY KEY,
	NAME VARCHAR(500) COMMENT 'название поставщика',
	SHEDULE VARCHAR(500) NULL COMMENT 'расписание',
	DATE_BEGIN DATETIME COMMENT 'Начало рабочего дня ',
	DATE_END DATETIME COMMENT 'Конец рабочего дня',
	CONSTRAINT UC_NAME_ID_DATE_BEGIN UNIQUE (NAME, DATE_BEGIN),
	FOREIGN KEY (NAME) REFERENCES T_CONTRACTOR_FIO(NAME),
	INDEX IND_NAME_ID_WORK_DAY (NAME)
);

# Задание 3
-- -------------------------------------------------------------------------------------------------------------------------------

DELIMITER //
DROP PROCEDURE IF EXISTS PROC_FILL_WORK_DAY //
CREATE PROCEDURE PROC_FILL_WORK_DAY (
									IN DAT_BEGIN DATETIME, 
									IN DAT_END DATETIME
									)
BEGIN
	DECLARE C,ID_ROW BIGINT DEFAULT 0;
	DECLARE CUR_SHEDULE CURSOR FOR SELECT ID FROM T_CONTRACTOR_DATA	WHERE DATE_BEGIN <= DAT_END AND DATE_END >= DAT_BEGIN; -- КУРСОР ДЛЯ СТРОК, РАСПИСАНИЕ КОТОРЫХ ПОПАДАЕТ В ЗАДАННЫЙ ИНТЕРВАЛ ВРЕМЕНИ
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET C=1;

	START TRANSACTION;
		OPEN CUR_SHEDULE;
			REPEAT
				FETCH CUR_SHEDULE INTO ID_ROW;
				IF NOT C THEN
					SELECT TCD.`SHEDULE` ,TCF.`NAME`, TCD.`DATE_BEGIN`, TCD.`DATE_END` FROM T_CONTRACTOR_DATA TCD 
					JOIN T_CONTRACTOR_FIO TCF 
					ON TCD.NAME_ID = TCF.`ID` 
					WHERE TCD.`ID` = ID_ROW
					INTO @SHED, @FIO_NAME, @D_BEG, @D_END; -- ПОЛУЧАЕМ ПАРАМЕТРЫ ДЛЯ СТРОКИ, КОТОРУЮ БУДЕМ РАЗБИРАТЬ В ЦИКЛЕ 

					-- УЧТЕМ СЛУЧАЙ, КОГДА РАСПИСАНИЕ НАЧИНАЕТСЯ НЕ С ПЕРВОГО ДНЯ
					SET @DAT_DIFF = DATEDIFF(DAT_BEGIN, @D_BEG);
					SET @START_POS = (SELECT IF(0 < @DAT_DIFF, @DAT_DIFF % CHAR_LENGTH(@SHED), 0));
					SET @SHED = SUBSTRING(@SHED, @START_POS+1);
						
					SET @DATE_SLID = (SELECT IF(@D_BEG > DAT_BEGIN, @D_BEG, DAT_BEGIN)); -- СКОЛЬЗЯЩАЯ ДАТА ДЛЯ ЦИКЛА ЗАПОЛНЕНИЯ
					SET @DATE_REAL_END = (SELECT IF(@D_END < DAT_END, @D_END, DAT_END)); -- ДАТА КОНЦА ОТСЧЕТА СОГЛАСНО ЗАДАННОГО ДИАПАЗОНА
					SET @REQ = '';
					SET @COUNT_ = 1; -- ЗАДАДИМ СЧЕТЧИК ДЛЯ СТРОКИ РАСПИСАНИЯ 
															
					LOOP_SHED: WHILE @DATE_SLID <= @DATE_REAL_END DO -- БЕРЕМ ДАТУ, ПРОВЕРЯЕМ, ЧТО ОНА НЕ БОЛЬШЕ КОНЕЧНОЙ ДАТЫ  
					
						SET @COUNT_ = (SELECT IF(@COUNT_ > CHAR_LENGTH(@SHED), 1,@COUNT_)); -- СБРОС СЧЕТЧИКА, ОБЕСПЕЧИВАЕТ ЦИКЛИЧНОСТЬ В ПОСТРОЕНИИ РАСПИССАНИЯ
						SET @SIGN = (SELECT SUBSTRING(@SHED, @COUNT_, 1)); -- ОПРЕДЕЛИМ БУКВУ Д-Н-С-В
						
					   CASE @SIGN
					      WHEN 'Д' THEN (SELECT 8,20 INTO @BEG_HOUR, @END_HOUR);
					      WHEN 'Н' THEN (SELECT 20,32 INTO @BEG_HOUR, @END_HOUR);
					      WHEN 'С' THEN (SELECT 8,32 INTO @BEG_HOUR, @END_HOUR); 
					      ELSE BEGIN
						      		SET @DATE_SLID = DATE_ADD(@DATE_SLID, INTERVAL 1 DAY);
									SET @COUNT_ = @COUNT_ + 1;
    								ITERATE LOOP_SHED;
						       END;
					    END CASE;

					   	-- СОБИРАЕМ ПАКЕТНЫЙ ЗАПРОС НА ВСТАВКУ
					    SET @REQ = CONCAT(@REQ,'("',@FIO_NAME,'","',@SIGN,'","',DATE_ADD(@DATE_SLID, INTERVAL @BEG_HOUR HOUR),'","',DATE_ADD(@DATE_SLID, INTERVAL @END_HOUR HOUR),'"),'); 
 						
						-- ИНКРЕМЕНТИРУЕМ ДАТУ С ПОМОЩЬЮ СЧЕТЧИКА СТРОКИ РАСПИСАНИЯ 
						SET @DATE_SLID = DATE_ADD(@DATE_SLID, INTERVAL 1 DAY);
						SET @COUNT_ = @COUNT_ + 1;
					END WHILE;
				
					-- ДЕЛАЕМ ПАКЕТНУЮ ВСТАВКУ В ЦЕЛЕВУЮ ТАБЛИЦУ
					SET @REQ = (SELECT TRIM( TRAILING ',' FROM @REQ)); -- УДАЛИТЬ ЛИШНЮЮ ЗАПЯТУЮ В КОНЦЕ
					SET @REQ = CONCAT('INSERT IGNORE INTO T_CONTRACTOR_WORK_DAY (NAME,SHEDULE,DATE_BEGIN,DATE_END) VALUES ',@REQ,';');
					PREPARE STMT1 FROM @REQ; -- ФОРМИРУЕМ ЗАПРОС НА ВСТАВКУ
					EXECUTE STMT1;
				END IF;
			UNTIL C END REPEAT;
		CLOSE CUR_SHEDULE;
	COMMIT;
END //
DELIMITER ;

-- вызовем процедуру, при этом соблюдаем форматт входных DATETIME в процедуре и пример в задании с параметрами '01.01.2019' - '08.01.2019' 
CALL PROC_FILL_WORK_DAY(STR_TO_DATE('01.01.2019','%d.%m.%Y'),STR_TO_DATE('31.12.2019','%d.%m.%Y')); 


# Задание 4
-- -------------------------------------------------------------------------------------------------------------------------------
# Сделать выборку содержащую сколько рабочих дней было у каждого поставщика
-- Если посчитать за 2019 год, то будет так:
SELECT `NAME`, COUNT(`DATE_BEGIN`) AS COUNT_WORKING_DAYS 
FROM T_CONTRACTOR_WORK_DAY TCWD 
WHERE `DATE_BEGIN` BETWEEN '2018-12-31' AND '2020-01-01' 
GROUP BY `NAME`;

# Сделать выборку поставщиков, у которыйх было больше 10 рабочих дней за январь 2019 года 
SELECT `NAME`, COUNT(`DATE_BEGIN`) AS COUNT_WORKING_DAYS 
FROM T_CONTRACTOR_WORK_DAY TCWD 
WHERE `DATE_BEGIN` BETWEEN '2018-12-31' AND '2019-02-01'
GROUP BY `NAME`
HAVING COUNT(*) > 10;

# Сделать выборку поставщиков, кто работал 14, 15 и 16 января 2019 года
SELECT `NAME` AS COUNT_WORKING_DAYS 
FROM T_CONTRACTOR_WORK_DAY TCWD 
WHERE `DATE_BEGIN` BETWEEN '2019-01-13' AND '2019-01-17'
GROUP BY `NAME`;





