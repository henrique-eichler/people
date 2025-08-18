package org.example.repository;

import org.example.model.People;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * In-memory repository for People entities.
 */
public class PeopleRepository {
    private final Map<Long, People> store = new ConcurrentHashMap<>();
    private final AtomicLong sequence = new AtomicLong(0);

    public People save(People people) {
        if (people.getId() == null) {
            people.setId(sequence.incrementAndGet());
        }
        store.put(people.getId(), copy(people));
        return findById(people.getId()).orElse(null);
    }

    public Optional<People> findById(Long id) {
        People p = store.get(id);
        return Optional.ofNullable(p == null ? null : copy(p));
    }

    public List<People> findAll() {
        List<People> list = new ArrayList<>();
        for (People p : store.values()) {
            list.add(copy(p));
        }
        return list;
    }

    public boolean deleteById(Long id) {
        return store.remove(id) != null;
    }

    public Optional<People> update(Long id, People update) {
        if (!store.containsKey(id)) {
            return Optional.empty();
        }
        update.setId(id);
        store.put(id, copy(update));
        return findById(id);
    }

    public void clear() {
        store.clear();
        sequence.set(0);
    }

    public long count() {
        return store.size();
    }

    private People copy(People src) {
        if (src == null) return null;
        return new People(src.getId(), src.getName(), src.getAge());
    }
}
