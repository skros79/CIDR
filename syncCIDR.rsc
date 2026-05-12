# ==============================================================================
# Скрипт: GitHub Dynamic Address-List Sync (RAM Mode)
# Версия: 1.0.0
# Дата: 12.05.2026
# Автор: skros79
# Ссылка на репозиторий: https://github.com/skros79/CIDR
# ==============================================================================
# Описание: Синхронизирует IP-адреса из файла на GitHub в address-list роутера.
# Работает в ОЗУ (без износа Flash-памяти). Реализует режим зеркала.
#
# ?? ВАЖНОЕ ОГРАНИЧЕНИЕ:
# Размер файла cidr.txt на GitHub не должен превышать 64 КБ (до ~3500-4000 строк).
# Превышение лимита приведет к обрезке данных и ложному удалению IP-адресов!
# ==============================================================================

# Настройки
:local fileName "cidr.txt"
:local url "https://raw.githubusercontent.com/skros79/CIDR/refs/heads/main/cidr.txt"

# 1. Загрузка данных напрямую в оперативную память (ОЗУ)
:local result
:do {
    :set result [/tool fetch url=$url mode=https output=user as-value]
} on-error={
    :log warning "!!!!!! Ошибка загрузки: Не удалось получить данные с сервера !!!!!!"
}

# Проверяем, что запрос завершился успешно и данные получены
:if ([:type $result] = "array" && ($result->"status") = "finished") do={
    :local content ($result->"data")
    :local contentLen [:len $content]

    :if ($contentLen < 5) do={ 
        :log warning "!!!!!! Данные получены, но они пустые или слишком малы ($contentLen байт) !!!!!!"
    } else={
        :local lineEnd 0
        :local lastEnd 0
        :local currentListName ""
        :local fileLists [:toarray ""]
        :local ipCount 0

        # 2. Парсинг данных из ОЗУ в двумерный массив
        :do {
            :set lineEnd [:find $content "\n" $lastEnd]
            :if ([:len $lineEnd] = 0) do={ :set lineEnd $contentLen }
            :local line [:pick $content $lastEnd $lineEnd]
            :set lastEnd ($lineEnd + 1)
            
            # Очистка строки от \r, \n, пробелов и табуляций
            :local cleanLine ""
            :for i from=0 to=([:len $line] - 1) do={
                :local char [:pick $line $i]
                :if ($char != " " && $char != "\r" && $char != "\n" && $char != "\t") do={ 
                    :set cleanLine ($cleanLine . $char) 
                }
            }

            :if ([:len $cleanLine] > 0) do={
                :if ([:pick $cleanLine 0 1] = ":") do={
                    # Нашли имя списка
                    :set currentListName [:pick $cleanLine 1 [:len $cleanLine]]
                    # Инициализируем массив для списка
                    :if ([:type ($fileLists->$currentListName)] = "nothing") do={
                        :set ($fileLists->$currentListName) [:toarray ""]
                    }
                } else={
                    # Нашли IPv4 адрес (по точке)
                    :if ([:find $cleanLine "."] > 0 && [:len $currentListName] > 0) do={
                        :set ipCount ($ipCount + 1)
                        :set ($fileLists->$currentListName) (($fileLists->$currentListName), $cleanLine)
                    }
                }
            }
        } while=($lastEnd < $contentLen)

        # 3. Синхронизация адрес-листов (Зеркалирование) с подсчетом
        :if ($ipCount > 0) do={
            :local addedCount 0
            :local removedCount 0

            :foreach listName,fileIPs in=$fileLists do={
                # Получаем текущие IP из MikroTik
                :local mtEntries [/ip firewall address-list find where list=$listName]
                :local mtIPs [:toarray ""]
                :foreach id in=$mtEntries do={
                    :local addr [/ip firewall address-list get $id address]
                    :set mtIPs ($mtIPs, $addr)
                }

                # А. Удаляем старые записи
                :foreach mtIP in=$mtIPs do={
                    :if ([:find $fileIPs $mtIP] < 0) do={
                        /ip firewall address-list remove [find where address=$mtIP and list=$listName]
                        :set removedCount ($removedCount + 1)
                    }
                }

                # Б. Добавляем новые записи
                :foreach fileIP in=$fileIPs do={
                    :if ([:find $mtIPs $fileIP] < 0) do={
                        /ip firewall address-list add address=$fileIP list=$listName comment=$listName
                        :set addedCount ($addedCount + 1)
                    }
                }
            }
            :log info "!!!!!! Address List RAM update finished. Total in file: $ipCount. Added: $addedCount. Removed: $removedCount."
        } else={
            :log warning "!!!!!! В полученных данных не найдено IPv4 адресов. Синхронизация пропущена !!!!!!"
        }
    }
} else={
    :log warning "!!!!!! Ошибка: Файл не был загружен в память роутера !!!!!!"
}
