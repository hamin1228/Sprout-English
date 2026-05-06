/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19-12.0.2-MariaDB, for osx10.21 (arm64)
--
-- Host: 127.0.0.1    Database: english_ai
-- ------------------------------------------------------
-- Server version	8.0.43

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*M!100616 SET @OLD_NOTE_VERBOSITY=@@NOTE_VERBOSITY, NOTE_VERBOSITY=0 */;

--
-- Table structure for table `scores_speaking`
--

DROP TABLE IF EXISTS `scores_speaking`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `scores_speaking` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` varchar(64) NOT NULL,
  `session_id` varchar(64) DEFAULT NULL,
  `transcript` text NOT NULL,
  `duration_ms` int NOT NULL,
  `words` int NOT NULL,
  `wpm` float NOT NULL,
  `filler_count` int NOT NULL,
  `silence_ratio` float NOT NULL,
  `rule_score` float NOT NULL,
  `gpt_score` float NOT NULL,
  `total_score` float NOT NULL,
  `feedback` json NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  KEY `idx_scores_speaking_user_created` (`user_id`,`created_at`),
  KEY `idx_scores_speaking_session` (`session_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `scores_speaking`
--

LOCK TABLES `scores_speaking` WRITE;
/*!40000 ALTER TABLE `scores_speaking` DISABLE KEYS */;
set autocommit=0;
INSERT INTO `scores_speaking` VALUES
(1,'u123',NULL,'ok',2000,1,30,0,0,0,90,36,'{\"summary\": \"자동 피드백(LLM 대체 스텁)\", \"suggestions\": [\"조금 더 또렷하고 빠르게 말해 보세요 (목표 120~150 wpm).\"], \"metrics_snapshot\": {\"wpm\": 30.0, \"words\": 1, \"filler_count\": 0, \"silence_ratio\": 0.0}}','2025-10-07 15:18:29'),
(2,'u123',NULL,'ok',2000,1,30,0,0,0,90,36,'{\"summary\": \"자동 피드백(LLM 대체 스텁)\", \"suggestions\": [\"조금 더 또렷하고 빠르게 말해 보세요 (목표 120~150 wpm).\"], \"metrics_snapshot\": {\"wpm\": 30.0, \"words\": 1, \"filler_count\": 0, \"silence_ratio\": 0.0}}','2025-10-07 15:19:09');
/*!40000 ALTER TABLE `scores_speaking` ENABLE KEYS */;
UNLOCK TABLES;
commit;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;

-- Dump completed on 2025-10-09 19:53:18
