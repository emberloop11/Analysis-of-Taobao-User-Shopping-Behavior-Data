# 第二阶段 数据统计与分析

# 2.1用户获取数据分析

# 创建浏览深度表
# PV:Page View，即页面浏览量或点击量，用户每次刷新即被计算一次。
# UV:Unique Visitor，独立访客，访问网站的一台电脑客户端为一个访客。
# CTR:浏览深度，PV/PU
CREATE TABLE PUV(
    dates char(10),
    PV INT(10),
    UV INT(10),
    CTR DECIMAL(10,2)
);

# 将计算结果导入到PUV表中
INSERT INTO PUV
SELECT
    DATE(date) AS dates, # 原本日期格式包含具体时间，现在仅保留到天
    COUNT(*) AS PU, # 页面浏览量pv_cnt:每天behavior_type为pv的数量是多少?
    COUNT(DISTINCT(user_id)) AS UV, # #独立访客数uv_cnt:每天有多少个访客?
    ROUND((COUNT(*))/COUNT(DISTINCT(user_id)),2) AS CTR # 浏览深度:PV/UV，这里保留2位小数
FROM
    clean_data
WHERE
    behavior_type = 'PV'
GROUP BY
    dates;
# CTR:浏览深度，在1.15到1.17之间波动，目大部分时间维持在1.16-1.17，说明平均每个独立访客浏览的页面数量相对固定，用户在网站上的浏览深度较为稳定，没有
# 出现明显的变化。这也侧面反映出网站内容对用户的吸引力在这段时间内没有太大改变，用户的浏览习惯相对稳定。

# 2.2用户留存分析
# 用户次日留存率:表自连接，以左表t1为主表，当t2中含有七1的日期的后一天才会显示出来，不然会显示null
SELECT date1, COUNT(t2.user_id)/COUNT(t1.user_id) AS 1_ret
FROM
(SELECT user_id,DATE(date) as date1 FROM clean_data GROUP BY user_id, date1) AS t1
LEFT JOIN
(SELECT user_id,DATE(date) as date2 FROM clean_data GROUP BY user_id, date2) AS t2
ON t1.user_id = t2.user_id
WHERE t2.date2 = DATE_ADD(t1.date1, INTERVAL 1 DAY )
GROUP BY date1
ORDER BY date1;

# 用户三日留存率
SELECT date1, COUNT(t2.user_id)/COUNT(t1.user_id) AS 1_ret
FROM
(SELECT user_id,DATE(date) as date1 FROM clean_data GROUP BY user_id, date1) AS t1
LEFT JOIN
(SELECT user_id,DATE(date) as date2 FROM clean_data GROUP BY user_id, date2) AS t2
ON t1.user_id = t2.user_id
WHERE t2.date2 = DATE_ADD(t1.date1, INTERVAL 3 DAY )
GROUP BY date1
ORDER BY date1;

# 创捷一个表格，将结果写入表格
CREATE TABLE retention_rate(
    dates CHAR(10),
    ret_1 FLOAT,
    ret_3 FLOAT
);

INSERT INTO retention_rate
    SELECT
        t1.date1 AS dates,
        COUNT(t2.user_id)/COUNT(t1.user_id) AS ret_1,
        COUNT(t3.user_id)/COUNT(t1.user_id) AS ret_3
FROM
(SELECT user_id,DATE(date) AS date1 FROM clean_data GROUP BY user_id, date1) t1
LEFT JOIN
(SELECT user_id,DATE(date) AS date2 FROM clean_data GROUP BY user_id, date2)  t2
ON t1.user_id = t2.user_id AND t2.date2 = DATE_ADD(t1.date1, INTERVAL 1 DAY )
LEFT JOIN
(SELECT user_id,DATE(date) AS date3 FROM clean_data GROUP BY user_id, date3)  t3
ON t1.user_id = t3.user_id AND t3.date3 = DATE_ADD(t1.date1, INTERVAL 3 DAY )
GROUP BY date1
ORDER BY date1;

# 跳失率:只有一次行为记录的用户/总用户数
SELECT (
    SELECT COUNT(user_id)
    FROM
        (SELECT user_id
         FROM clean_data
         GROUP BY user_id
         HAVING COUNT(behavior_type) = 1) t1
           )/(SELECT SUM(UV)FROM puv) AS bounce_rate;

# 2.2用户行为分析 -- 时间维度（小时粒度）
CREATE TABLE hour_behavior(
    dates CHAR(10),
    hours CHAR(2),
    pv_cnt INT,
    cart_cnt INT,
    fav_cnt INT,
    buy_cnt INT
);

INSERT INTO hour_behavior
# 小时维度
SELECT DATE(timestamp) AS dates,HOUR(timestamp) AS hours,
       COUNT(IF(behavior_type = 'pv',1,null)) AS pv_cnt,
       COUNT(IF(behavior_type = 'cart',1,null)) AS cart_cnt,
       COUNT(IF(behavior_type = 'fav',1,null)) AS fav_cnt,
       COUNT(IF(behavior_type = 'buy',1,null)) AS buy_cnt
FROM clean_data
GROUP BY dates,hours
ORDER BY dates,hours;

# 2.3用户转化率分析
#这里漏斗第一层算的是总UV，也就是所有有行为的用户数量和浏览行为的用户数量450390，两个数并不一样，为什么呢?
# 因为第三层计算有购买行为的用户数的时候包含了一部分没有浏览就直接购买的人，这部分人可能是在统计时段之前浏览的商品，或者是直接在购物车直接购买的

CREATE TABLE Conversion_Rate(
    total_UV INT,
    fav_cart_UV INT,
    buy_cart_UV INT,
    pv_to_favcart_rate FLOAT,
    favcart_to_buy_rate FLOAT,
    pv_to_buy_rate FLOAT
);

INSERT INTO Conversion_Rate
# 第一层:总UV 987982
WITH funnel AS (
    SELECT COUNT(DISTINCT user_id) AS total_UV FROM clean_data
),
# 第二层:有收藏或加购行为的用户数834413
fav_cart_users AS (
    SELECT COUNT(DISTINCT user_id) AS fav_cart_UV
    FROM clean_data
    WHERE behavior_type IN ('fav','cart')
    ),
# 第三层:最终购买用户数629777
buy_users AS (
    SELECT COUNT(DISTINCT user_id) AS buy_cart_UV
    FROM clean_data
    WHERE behavior_type = 'buy'
)
SELECT f.total_UV AS total_UV,fc.fav_cart_UV AS fav_cart_UV,bu.buy_cart_UV AS buy_cart_UV,
              # 计算转化率
       ROUND(fc.fav_cart_UV * 100 / f.total_UV,2) AS pv_to_favcart_rate, # 84.46%
       ROUND(bu.buy_cart_UV * 100 / fc.fav_cart_UV,2) AS favcart_to_buy_rate, # 75.48%
       ROUND(bu.buy_cart_UV * 100 / f.total_UV,2) AS pv_to_buy_rate # 63.74%
FROM funnel AS f,fav_cart_users AS fc,buy_users as bu;
# 1.浏览-收藏加购转化率84.46%，可能是因为双十二前夕用户主动搜索日标商品，浏览后立即收藏/加购(需求明确，决策链路短加上平台强引导(如“收藏领券”加吨
# 享优先发货”
# 2.收藏加购购买转化率75.48%，可能是促销力度大(如满减、限时折扣)，用户在双十二前夕提前加购，等待大促时集中购买。商品多为刚需品或低价高频商品
# (如日用品、零食)，用户决策成本低。
# 3.总体购买转化率63.74%，远超行业水平(常规电商为1%-5%，大促期间可能达5%-15%)，主要由无浏览直接购买用户(53%)驱动。

# 2.4.用户行为路径分析
# 先给用户行为进行标准化，也就是(浏览,收藏加购.购买)四种行为，有行为就标为1，没有就标为0，比如(1011)就是(浏览了，没有收藏，加购了，购买了)
# 每个用户每个商品的行为数量统计，存为视图
CREATE VIEW user_item_behavior AS
SELECT
    user_id,
    item_id,
    COUNT(IF(behavior_type = 'pv', 1, NULL)) AS pv_cnt,
    COUNT(IF(behavior_type = 'fav', 1, NULL)) AS fav_cnt,
    COUNT(IF(behavior_type = 'cart', 1, NULL)) AS cart_cnt,
    COUNT(IF(behavior_type = 'buy', 1, NULL)) AS buy_cnt
FROM clean_data
GROUP BY user_id, item_id;


# 用户行为标准化，存为视图
CREATE VIEW user_behavior_standard AS
SELECT
user_id,
item_id,
CASE WHEN pv_cnt > 0 THEN 1 ELSE 0 END AS 浏览,
CASE WHEN fav_cnt > 0 THEN 1 ELSE 0 END AS 收藏,
CASE WHEN cart_cnt > 0 THEN 1 ELSE 0 END AS 加购,
CASE WHEN buy_cnt > 0 THEN 1 ELSE 0 END AS 购买
FROM user_item_behavior;

# 拼接行为路径，存到表中备用
CREATE TABLE user_behavior_path(
user_id CHAR(9),
item_id CHAR(9),
user_behavior_path CHAR(4)
);

INSERT INTO user_behavior_path
SELECT
    user_id,
    item_id,
CONCAT(浏览, 收藏, 加购, 购买) AS user_behavior_path
FROM user_behavior_standard;

# 统计时段内无浏览、直接购买的用户数量 331707
SELECT COUNT(DISTINCT user_id) AS buy_user
FROM user_behavior_path
WHERE user_behavior_path IN ('0001', '0101', '0011', '0111');

# 统计时段内无浏览收藏加购、直接购买的用户数量 289681
SELECT COUNT(DISTINCT user_id) AS buy_user
FROM user_behavior_path
WHERE user_behavior_path = '0001';


# 浏览-收藏/加购-购买 行为路径转化率

# 漏斗第一层：浏览的用户数量 983847
SELECT COUNT(DISTINCT user_id) AS pv_UV
FROM clean_data
WHERE behavior_type = 'pv';

# 漏斗第二层：收藏或加购的用户数量 691553
SELECT COUNT(DISTINCT user_id) AS fav_cart_user
FROM user_behavior_path
WHERE user_behavior_path IN ('1100', '1101', '1110', '1111', '1010', '1011');

# 漏斗第三层：最后购买的用户数量 207840
SELECT COUNT(DISTINCT user_id) AS buy_user
FROM user_behavior_path
WHERE user_behavior_path IN ('1101', '1111', '1011');

# 转化率计算
SELECT
    ROUND(735830 * 100.0 / 984114, 2) AS pv_to_favcart_rate,
    ROUND(557048 * 100.0 / 735830, 2) AS favcart_to_buy_rate,
    ROUND(557048 * 100.0 / 984114, 2) AS overall_conversion_rate;

# 2.5用户生命周期
# 数据中没有订单金额，无法直接计算用户生命周期价值LTV=平均用户付费金额x平均用户生命周期，但可以通过复购率间接评估用户价值或生命周期
# 通过计算可以看到复购率达到了50.58%，超半数用户在统计时段内分多天购买，可能为大促囤货或刚需采购，反映短期活跃性强，但需结合长期数据判断是否为持续行为

# 计算复购率
WITH user_purchase_dates AS (
    SELECT
        user_id,
        date,# 按天去重，假设同一天购买的为同一个订单
        COUNT(DISTINCT item_id) AS items_per_day
    FROM clean_data
    WHERE behavior_type = 'buy'
    GROUP BY user_id, date
),
user_purchase_count AS (
    SELECT
        user_id,
        COUNT(*) AS purchase_days
    FROM user_purchase_dates
    GROUP BY user_id
)
SELECT
    SUM(CASE WHEN purchase_days >= 2 THEN 1 ELSE 0 END) AS repeat_users, # 318542
    COUNT(DISTINCT user_id) AS total_users, # 629777
    ROUND(SUM(CASE WHEN purchase_days >= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT user_id), 2) AS true_repeat_rate # 50.58%
FROM user_purchase_count;


# 用户分层RFM模型
# 这里用RFM模型进行用户分层，该模型由以下三个指标组成:
# R:最近一次消费至今的时间，离得越远，用户越有流失可能
# F:一定时间内重复消费频率，频次低，需要用一次性手段(比如促销、赠礼)，频次高，用持续性手段(积分)来维护
# M:一定时间内累计消费金额，消费越多，用户价值越高，越应该重点关注
# 因为数据中没有订单金额，所以只计算R和F
# 创建表user_rf存储R值和F值
DROP TABLE IF EXISTS user_rf;
CREATE TABLE user_rf(
user_id INT,
recency INT,
frequency INT
);

# 计算每个用户的R值和F值
INSERT INTO user_rf
SELECT
    user_id,
    DATEDIFF('2017-12-04', MAX(date)) AS recency, # R值:距离最近一次购买的天数
    COUNT(DISTINCT date) AS frequency # F值:购买的不同日期数
FROM clean_data
WHERE behavior_type = 'buy'
GROUP BY user_id;

# 查看R值和F值的范围
SELECT MAX(recency), MIN(recency), MAX(frequency), MIN(frequency)
FROM user_rf;

# 先查看R值和F值的分布，根据分布来分配分数
# 由R值和分布可以看到:
# 1的用户(173k)明显多于2的(130k)，值得单独列为最高分
# 3-4用户量显著下降但仍有相当规模
# 5及以后用户量相对平稳下降
# 查看R值分布
SELECT
    recency, COUNT(*) AS users
FROM user_rf
GROUP BY recency
ORDER BY recency DESC ;
# recency users
# 9       34227
# 8       43390
# 7       50577
# 6       57899
# 5       57899
# 4       73672
# 3       89369
# 2       105944
# 1       174698

# 由F值和分布可以看到:
# 用户数量呈现典型的“长尾分布”(1-2次购买的用户占绝大多数，高频用户数量急剧减少)
# 查看F值分布
SELECT
    frequency, COUNT(*) AS users
FROM user_rf
GROUP BY frequency
ORDER BY frequency;
# frequency users
# 1         311235
# 2         181951
# 3         83895
# 4         33866
# 5         12547
# 6         4295
# 7         1467
# 8         521

# 创建表rfm存储用户分层结果
DROP TABLE IF EXISTS rfm;
CREATE TABLE rfm(
    user_id INT,
    recency INT,
    frequency INT,
    r_score INT,
    f_score INT,
    avg_r_score DECIMAL(5,2),
    avg_f_score DECIMAL(5,2),
    user_segment VARCHAR(50)
);

# 根据分布来分配分数并进行用户分层
INSERT INTO rfm
WITH user_rf_scores AS (
    SELECT
        ur.user_id,
        ur.recency,
        ur.frequency,
        CASE
            WHEN ur.recency = 1 THEN 4
            WHEN ur.recency = 2 THEN 3
            WHEN ur.recency BETWEEN 3 AND 4 THEN 2
            ELSE 1
        END AS r_score,
        CASE
            WHEN ur.frequency BETWEEN 7 AND 9 THEN 4
            WHEN ur.frequency BETWEEN 5 AND 6 THEN 3
            WHEN ur.frequency BETWEEN 3 AND 4 THEN 2
            ELSE 1
        END AS f_score
    FROM user_rf ur
),
score_avg AS (
    SELECT
        AVG(r_score) AS avg_r_score,
        AVG(f_score) AS avg_f_score
    FROM user_rf_scores
)
SELECT
    u.user_id,
    u.recency,
    u.frequency,
    u.r_score,
    u.f_score,
    s.avg_r_score,
    s.avg_f_score,
    CASE
        WHEN u.r_score >= s.avg_r_score AND u.f_score >= s.avg_f_score THEN '价值用户'
        WHEN u.r_score >= s.avg_r_score AND u.f_score < s.avg_f_score THEN '发展用户'
        WHEN u.r_score < s.avg_r_score AND u.f_score >= s.avg_f_score THEN '保持用户'
        ELSE '挽留用户'
    END AS user_segment
FROM user_rf_scores u
CROSS JOIN score_avg s;

# 统计各分区用户数
SELECT user_segment, COUNT(user_id) AS user_count
FROM rfm
GROUP BY user_segment;
# user_segment user_count
# 保持用户       18717
# 发展用户       252138
# 价值用户       117874
# 挽留用户       241048

# 2.6商品热度分析

# 品类浏览量前十
CREATE TABLE category_popularity(
    category_id INT,
    category_pv INT
);

INSERT INTO category_popularity
SELECT category_id, COUNT(*) AS category_pv
FROM clean_data
WHERE behavior_type = 'pv'
GROUP BY category_id
ORDER BY category_pv DESC
LIMIT 10;

# 商品浏览量前十
CREATE TABLE item_popularity(
    item_id INT,
    item_pv INT
);

INSERT INTO item_popularity
SELECT item_id, COUNT(*) AS item_pv
FROM clean_data
WHERE behavior_type = 'pv'
GROUP BY item_id
ORDER BY item_pv DESC
LIMIT 10;

# 品类点击量和购买量
CREATE TABLE category_popularity_total(
    category_id INT,
    category_pv INT,
    category_buy INT
);

# 使用CASE WHEN条件聚合
INSERT INTO category_popularity_total (category_id, category_pv, category_buy)
SELECT
    category_id,
    SUM(CASE WHEN behavior_type = 'pv' THEN 1 ELSE 0 END) AS category_pv,
    SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS category_buy
FROM clean_data
WHERE behavior_type IN ('pv', 'buy')
GROUP BY category_id
ORDER BY category_pv DESC;

